const { test } = require('node:test')
const assert = require('node:assert')
const cat = require('../server/categorize.cjs')
const rec = require('../server/reconcile.cjs')

test('categorize: longest match wins, so specific beats generic', () => {
  const s = cat.suggest({ merchant: 'AMAZON PRIME VIDEO' })
  assert.equal(s.category, 'Subscriptions')
  assert.equal(cat.suggest({ merchant: 'UBER TRIP 4821' }).category, 'Transport')
  assert.equal(cat.suggest({ merchant: '' }), null, 'no text -> no guess')
})

test('categorize: suggests only, never mutates', () => {
  const rows = [{ id: 1, merchant: 'Starbucks', category: 'Other' }, { id: 2, merchant: '', category: null }]
  const out = cat.suggestBatch(rows)
  assert.equal(out.length, 1)
  assert.equal(out[0].id, 1)
  assert.equal(out[0].current, 'Other', 'reports the existing value rather than overwriting')
})

test('reconcile: drift is zero when the ledger explains the balance change', () => {
  const r = rec.reconcileAccount({
    account: 'Cash', from: '2026-01-01', to: '2026-01-31',
    opening_cents: 100000, closing_cents: 92500,
    transactions: [
      { direction: 'expense', amount_cents: 10000 },
      { direction: 'income', amount_cents: 2500 },
    ],
  })
  assert.equal(r.ledger_movement_cents, -7500)
  assert.equal(r.drift_cents, 0)
  assert.equal(r.balanced, true)
})

test('reconcile: a missing transaction shows up as drift', () => {
  const r = rec.reconcileAccount({
    account: 'Cash', from: '2026-01-01', to: '2026-01-31',
    opening_cents: 100000, closing_cents: 80000,
    transactions: [{ direction: 'expense', amount_cents: 10000 }],
  })
  assert.equal(r.drift_cents, -10000, '$100 of spending is unaccounted for')
  assert.equal(r.balanced, false)
  assert.equal(r.within_tolerance, false)
})

test('reconcile: transfers move their own account balance', () => {
  assert.equal(rec.delta({ direction: 'transfer_in', amount_cents: 500 }), 500)
  assert.equal(rec.delta({ direction: 'transfer_out', amount_cents: 500 }), -500)
})

test('budgetStatus flags over and warning', () => {
  const out = rec.budgetStatus({
    budgets: [{ category: 'Food', period: 'monthly', limit_cents: 10000 },
              { category: 'Transport', period: 'monthly', limit_cents: 10000 }],
    spendByCategory: [{ category: 'Food', cents: 12000 }, { category: 'Transport', cents: 8500 }],
  })
  assert.equal(out[0].category, 'Food')
  assert.equal(out[0].status, 'over')
  assert.equal(out[1].status, 'warning')
})

test('a "Total" budget counts all spending, not one category', () => {
  const out = rec.budgetStatus({
    budgets: [{ category: 'Total', period: 'monthly', limit_cents: 30000 }],
    spendByCategory: [{ category: 'Food', cents: 12000 }, { category: 'Transport', cents: 8500 }],
  })
  assert.equal(out[0].spent_cents, 20500)
  assert.equal(out[0].remaining_cents, 9500)
})

test('reviewQueue surfaces only unconfirmed non-import rows', () => {
  const q = rec.reviewQueue([
    { id: 1, reviewed: 0, source: 'chatgpt', amount_cents: 100 },
    { id: 2, reviewed: 1, source: 'chatgpt', amount_cents: 100 },
    { id: 3, reviewed: 0, source: 'import', amount_cents: 100 },
  ])
  assert.deepEqual(q.map((r) => r.id), [1], 'imported history is trusted; LLM rows are not')
})
