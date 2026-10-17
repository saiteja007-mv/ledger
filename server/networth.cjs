// networth.cjs — per-account balances as of now, grouped, plus net worth in USD.
//
// Lifted verbatim from web/index.cjs (ACCOUNT_KINDS, extendAccount, extendAccounts and the
// /api/networth route) so the iOS API (web/api.cjs) shows exactly the balances the web app shows.
// ponytail: web/index.cjs still carries its own copy; point it at this module the next time that
// file is edited, and there is one copy again.
const fs = require('node:fs')
const path = require('node:path')
const db = require('./db.cjs')
const reconcile = require('./reconcile.cjs')
const fx = require('./fx.cjs')

const DATA_DIR = path.join(__dirname, '..', '.data')

// accounts.kind may be empty on older rows; these name lists fill it in. Your own account names
// live in .data/account-kinds.json (gitignored), e.g. {"credit":["Visa 1234"],"checking":["Checking"]}.
const ACCOUNT_KINDS = (() => {
  const d = { credit: [], checking: ['Checking'], cash: ['Cash'], people: ['Splitwise', 'Friends'] }
  try { return { ...d, ...JSON.parse(fs.readFileSync(path.join(DATA_DIR, 'account-kinds.json'), 'utf8')) } } catch { return d }
})()
const CARD_NAMES = new Set(ACCOUNT_KINDS.credit)
const BANKING_NAMES = new Set(ACCOUNT_KINDS.checking)
const CASH_NAMES = new Set(ACCOUNT_KINDS.cash)
const PEOPLE_NAMES = new Set(ACCOUNT_KINDS.people)

function inferKind(name) {
  if (CARD_NAMES.has(name)) return 'credit'
  if (BANKING_NAMES.has(name)) return 'checking'
  if (CASH_NAMES.has(name)) return 'cash'
  if (PEOPLE_NAMES.has(name)) return 'people'
  return null
}

const GROUP_LABELS = { banking: 'Banking', cards: 'Cards', cash: 'Cash', people: 'People' }
const GROUP_ORDER = ['banking', 'cards', 'cash', 'people']
function groupKeyFor(kind) {
  if (kind === 'checking') return 'banking'
  if (kind === 'credit') return 'cards'
  if (kind === 'cash' || kind === 'wallet' || kind === 'virtual') return 'cash'
  return 'people'
}

// One account row extended with net-worth fields. `signed_cents` is the account's contribution to
// net worth (a liability's owed balance flips sign); `drift_cents` is ledger movement recorded
// strictly AFTER the latest reported balance; `current_cents` is the balance as of now, in the
// account's own convention (owed, for a card).
function extendAccount(a, usd_rate = 1) {
  const tx = db.listTransactions({ account: a.name, limit: 100000 })
  const snaps = db.listBalances(a.name)
  const kind_resolved = a.kind || inferKind(a.name) || 'other'
  const is_liability = kind_resolved === 'credit'
  const implied_cents = reconcile.impliedBalance(tx)
  const latest = snaps[0] || null
  const anchor = latest ? { as_of_date: latest.as_of_date, cents: latest.balance_cents } : null
  const verified = snaps.length > 0
  const raw_drift_cents = anchor
    ? tx.filter((t) => t.posted_at.slice(0, 10) > anchor.as_of_date).reduce((s, t) => s + reconcile.delta(t), 0)
    : null
  const drift_cents = raw_drift_cents == null ? null : (is_liability ? -raw_drift_cents : raw_drift_cents)
  const current_cents = anchor ? anchor.cents + (drift_cents ?? 0) : implied_cents
  const signed_cents = Math.round((is_liability ? -current_cents : current_cents) * usd_rate)
  return {
    ...a, transactions: tx.length, implied_cents, latest_balance: anchor ? { as_of_date: anchor.as_of_date, cents: anchor.cents } : null,
    kind_resolved, is_liability, verified, anchor, signed_cents, signed_is_estimate: !anchor,
    drift_cents, current_cents, group: groupKeyFor(kind_resolved),
  }
}

// Net worth is in USD, so each non-USD account is converted at today's live rate. If the rate
// can't be fetched the account counts at 1:1 rather than breaking the page; usd_rate: null flags it.
async function extendAccounts() {
  const out = []
  for (const a of db.listAccounts()) {
    let rate = 1, ok = true
    try { rate = await fx.usdRate(a.currency) } catch (e) { ok = false; console.error(`[fx] ${e.message}`) }
    out.push({ ...extendAccount(a, rate), usd_rate: ok ? rate : null })
  }
  return out
}

async function netWorth() {
  const accounts = await extendAccounts()
  const groups = GROUP_ORDER.map((key) => {
    const rows = accounts.filter((a) => a.group === key)
    return { key, label: GROUP_LABELS[key], total_cents: rows.reduce((s, a) => s + a.signed_cents, 0), accounts: rows }
  })
  const assets_cents = accounts.filter((a) => !a.is_liability).reduce((s, a) => s + a.signed_cents, 0)
  const liabilities_cents = accounts.filter((a) => a.is_liability).reduce((s, a) => s - a.signed_cents, 0)
  return {
    assets_cents, liabilities_cents, net_cents: assets_cents - liabilities_cents,
    unverified_count: accounts.filter((a) => !a.verified).length, groups,
  }
}

module.exports = { extendAccounts, netWorth }
