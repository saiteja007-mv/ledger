#!/usr/bin/env node
// First setup from one JSON plan: your accounts with today's balances, and your budgets. Made for an agent to
// run after asking you (AGENTS.md, "First setup"); safe to run again: accounts and budgets are upserts and a
// balance for the same day replaces itself.
//   node scripts/setup.cjs example                  print an example plan
//   node scripts/setup.cjs apply plan.json          write it (--dry-run: only check it)
//   node scripts/setup.cjs show                     what is set up now, to read back
//
// Plan: {"accounts": [{name, kind, currency?, institution?, balance?, as_of?}], "budgets": [{category, limit, period?}]}
//   kind     checking (any bank account) | credit (a card) | cash | wallet | people (friends who owe you)
//   balance  today's balance in the account's currency; for a card, what you owe, as a positive number
//   as_of    the date of that balance, YYYY-MM-DD (default today)
//   budgets  category "Total" is the overall monthly limit; period monthly (default) or weekly
const fs = require('node:fs')
const db = require('../server/db.cjs')
const categorize = require('../server/categorize.cjs')

const KINDS = ['checking', 'credit', 'cash', 'wallet', 'people']
const p2 = (n) => String(n).padStart(2, '0')
const now = new Date()
const today = `${now.getFullYear()}-${p2(now.getMonth() + 1)}-${p2(now.getDate())}`

const EXAMPLE = {
  accounts: [
    { name: 'Checking', kind: 'checking', currency: 'USD', institution: 'My Bank', balance: 2450.1 },
    { name: 'Visa 1234', kind: 'credit', currency: 'USD', balance: 312.4 },
    { name: 'Cash', kind: 'cash', currency: 'USD', balance: 60 },
    { name: 'Friends', kind: 'people', currency: 'USD', balance: 0 },
  ],
  budgets: [{ category: 'Total', limit: 2500 }, { category: 'Food', limit: 400 }, { category: 'Groceries', limit: 300 }],
}

// Every problem in the plan at once, so one round of questions fixes them all.
function check(plan) {
  const problems = []
  const say = (where, what) => problems.push(`${where}: ${what}`)
  if (!plan || typeof plan !== 'object') return ['the plan must be a JSON object']
  const accounts = plan.accounts ?? []
  const budgets = plan.budgets ?? []
  if (!Array.isArray(accounts) || !Array.isArray(budgets)) return ['accounts and budgets must be lists']
  const names = new Set()
  accounts.forEach((a, i) => {
    const at = `accounts[${i}]${a?.name ? ` "${a.name}"` : ''}`
    if (typeof a?.name !== 'string' || !a.name.trim() || a.name.length > 80) return say(at, 'needs a name (up to 80 characters)')
    if (names.has(a.name.trim().toLowerCase())) say(at, 'appears twice')
    names.add(a.name.trim().toLowerCase())
    if (!KINDS.includes(a.kind)) say(at, `kind must be one of ${KINDS.join(', ')}`)
    if (a.currency != null && !/^[A-Z]{3}$/.test(a.currency)) say(at, 'currency must be a 3-letter code like USD or INR')
    if (a.balance != null && !(typeof a.balance === 'number' && Number.isFinite(a.balance))) say(at, 'balance must be a number')
    if (a.as_of != null && (!/^\d{4}-\d{2}-\d{2}$/.test(a.as_of) || a.as_of > today)) say(at, 'as_of must be a past date, YYYY-MM-DD')
    const existing = db.accountByName(a.name.trim())
    if (existing && a.currency && existing.currency !== a.currency) say(at, `already exists in ${existing.currency}; its currency can't change here`)
  })
  budgets.forEach((b, i) => {
    const at = `budgets[${i}]${b?.category ? ` "${b.category}"` : ''}`
    if (typeof b?.category !== 'string' || !b.category.trim()) say(at, 'needs a category')
    if (!(typeof b?.limit === 'number' && b.limit > 0)) say(at, 'limit must be a positive number')
    if (b?.period != null && !['monthly', 'weekly'].includes(b.period)) say(at, 'period must be monthly or weekly')
  })
  return problems
}

function apply(plan) {
  for (const a of plan.accounts ?? []) {
    const name = a.name.trim()
    db.upsertAccount({ name, kind: a.kind, institution: a.institution ?? null, currency: a.currency ?? 'USD' })
    if (a.balance != null) {
      db.recordBalance({ account: name, as_of_date: a.as_of ?? today, balance_cents: db.toCents(a.balance), currency: a.currency ?? 'USD' })
    }
  }
  for (const b of plan.budgets ?? []) {
    db.setBudget({ category: b.category.trim(), period: b.period ?? 'monthly', limit_cents: db.toCents(b.limit) })
  }
}

function show() {
  const known = new Set([...db.distinctCategories(), ...categorize.DEFAULT_RULES.map((r) => r.category), 'Total'])
  return {
    accounts: db.listAccounts().map((a) => {
      const latest = db.listBalances(a.name)[0]
      return { name: a.name, kind: a.kind, currency: a.currency, institution: a.institution,
        balance: latest ? latest.balance_cents / 100 : null, as_of: latest?.as_of_date ?? null }
    }),
    budgets: db.listBudgets().map((b) => ({ category: b.category, period: b.period, limit: b.limit_cents / 100,
      ...(known.has(b.category) ? {} : { note: 'no transaction uses this category yet' }) })),
    stats: db.stats(),
  }
}

if (require.main === module) {
  const [command, file] = process.argv.slice(2)
  if (command === 'apply' || command === 'show') db.initDb()
  if (command === 'example') {
    console.log(JSON.stringify(EXAMPLE, null, 2))
  } else if (command === 'apply') {
    if (!file) { console.error('usage: node scripts/setup.cjs apply plan.json [--dry-run]'); process.exit(2) }
    let plan
    try { plan = JSON.parse(fs.readFileSync(file, 'utf8')) } catch (e) { console.error(`can't read ${file}: ${e.message}`); process.exit(2) }
    const problems = check(plan)
    if (problems.length) { console.error(`Nothing written. Fix these first:\n- ${problems.join('\n- ')}`); process.exit(1) }
    if (process.argv.includes('--dry-run')) { console.log('plan OK (dry run, nothing written)'); process.exit(0) }
    apply(plan)
    console.log(JSON.stringify(show(), null, 2))
  } else if (command === 'show') {
    console.log(JSON.stringify(show(), null, 2))
  } else {
    console.error('usage: node scripts/setup.cjs example | apply plan.json [--dry-run] | show')
    process.exit(2)
  }
}

module.exports = { check, apply, show, EXAMPLE }
