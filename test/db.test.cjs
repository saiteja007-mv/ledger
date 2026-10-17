const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const db = require('../server/db.cjs')

// Fresh throwaway DB per run — never touch .data/finance.sqlite from tests.
const tmp = path.join(os.tmpdir(), `finance-test-${process.pid}.sqlite`)
try { fs.unlinkSync(tmp) } catch {}
db.initDb(tmp)
process.on('exit', () => { try { fs.unlinkSync(tmp) } catch {} })

test('toCents kills float noise from the export', () => {
  // These exact values appear in the real xlsx (37 rows carry >2dp artifacts).
  assert.equal(db.toCents('79.34999999999999'), 7935)
  assert.equal(db.toCents('84.68000000000001'), 8468)
  assert.equal(db.toCents(0.1 + 0.2), 30)
  assert.equal(db.toCents('1,234.56'), 123456)
  assert.equal(db.toCents(''), null)
})

test('natural key keeps genuine same-day repeats distinct', () => {
  // The source has 8 real cases of two identical-amount fares on one day. A date-only
  // key would merge them and silently delete spending; the timestamp must disambiguate.
  const base = { account: 'Cash', amount_cents: 500, currency: 'USD', direction: 'expense' }
  const a = db.externalId({ ...base, posted_at: '2026-02-17T09:12:00' })
  const b = db.externalId({ ...base, posted_at: '2026-02-17T18:44:00' })
  const same = db.externalId({ ...base, posted_at: '2026-02-17T09:12:00' })
  assert.notEqual(a, b, 'same day, different time must not collide')
  assert.equal(a, same, 'identical input must be stable')
})

test('upsert is idempotent — re-syncing the same data does not double-count', () => {
  const items = [
    { account: 'Main Checking', posted_at: '2026-03-01T10:00:00', direction: 'expense', amount_cents: 2500, category: 'Food' },
    { account: 'Main Checking', posted_at: '2026-03-01T11:00:00', direction: 'income', amount_cents: 100000 },
  ]
  const first = db.upsertTransactions(items, { source: 'chatgpt' })
  assert.equal(first.inserted, 2)
  const second = db.upsertTransactions(items, { source: 'chatgpt' })
  assert.equal(second.inserted, 0, 'second sync must insert nothing')
  assert.equal(second.updated, 2)
  const rows = db.listTransactions({ account: 'Main Checking' })
  assert.equal(rows.length, 2, 'still exactly 2 rows after two syncs')
})

test('summary excludes transfers so they cannot inflate income and expense', () => {
  db.upsertTransactions([
    { account: 'Cash', posted_at: '2026-04-01T10:00:00', direction: 'transfer_out', amount_cents: 50000, counter_account: 'Friends' },
    { account: 'Friends', posted_at: '2026-04-01T10:00:00', direction: 'transfer_in', amount_cents: 50000, counter_account: 'Cash' },
  ], { source: 'import' })
  const s = db.summary({ from: '2026-04-01', to: '2026-04-02' })
  assert.equal(s.income_cents, 0, 'transfer_in must not count as income')
  assert.equal(s.expense_cents, 0, 'transfer_out must not count as expense')
  assert.equal(s.transfers_excluded, 2)
})

test('negative amounts are rejected — direction carries the sign', () => {
  assert.throws(() => db.upsertTransaction({
    account: 'Cash', posted_at: '2026-05-01T10:00:00', direction: 'expense', amount_cents: -100,
  }), /positive/)
})

test('cross-currency requires an fx rate and stores a base amount', () => {
  assert.throws(() => db.upsertTransaction({
    account: 'Intl', posted_at: '2026-06-01T10:00:00', direction: 'expense',
    amount_cents: 10000, currency: 'INR', base_currency: 'USD',
  }), /fx_rate required/)

  db.upsertTransaction({
    account: 'Intl', posted_at: '2026-06-01T10:00:00', direction: 'expense',
    amount_cents: 100000, currency: 'INR', base_currency: 'USD', fx_rate: 0.012,
  })
  const r = db.listTransactions({ account: 'Intl' })[0]
  assert.equal(r.amount_cents, 100000)
  assert.equal(r.base_amount_cents, 1200, 'INR 1000.00 at 0.012 -> USD 12.00')
})

test('void is soft — money is never hard-deleted', () => {
  const { external_id } = db.upsertTransaction({
    account: 'Cash', posted_at: '2026-07-01T10:00:00', direction: 'expense', amount_cents: 999,
  })
  const row = db.listTransactions({ account: 'Cash', from: '2026-07-01', to: '2026-07-02' })[0]
  db.voidTransaction(row.id, 'duplicate')
  assert.equal(db.listTransactions({ account: 'Cash', from: '2026-07-01', to: '2026-07-02' }).length, 0)
  const withVoided = db.listTransactions({ account: 'Cash', from: '2026-07-01', to: '2026-07-02', include_voided: true })
  assert.equal(withVoided.length, 1, 'row still exists, just hidden')
  assert.ok(withVoided[0].voided_at)
  assert.ok(external_id)
})

test('receipt matching is conservative on amount and date window', () => {
  db.upsertTransaction({ account: 'Bofa Credit card', posted_at: '2026-08-02T13:00:00', direction: 'expense', amount_cents: 4210 })
  const hit = db.matchReceiptToTransaction({ total_cents: 4250, purchased_at: '2026-08-02T13:05:00' })
  assert.ok(hit, 'within 2% and same day should match')
  const miss = db.matchReceiptToTransaction({ total_cents: 9900, purchased_at: '2026-08-02T13:05:00' })
  assert.equal(miss, null, 'far-off amount must not match')
  const far = db.matchReceiptToTransaction({ total_cents: 4210, purchased_at: '2026-09-20T13:00:00' })
  assert.equal(far, null, 'outside the day window must not match')
})

test('every write lands in the audit log', () => {
  const before = db.listAudit(200).length
  db.upsertTransactions([{ account: 'Cash', posted_at: '2026-08-05T09:00:00', direction: 'expense', amount_cents: 111 }])
  assert.ok(db.listAudit(200).length > before)
})

test('receipt lines parse into comparable item keys and unit prices', () => {
  // Weighed produce: the "@ $/lb" annotation wins over total/qty.
  const onion = db.parseReceiptLine({ name: 'Red onion — 3.53 lb @ $0.59/lb', price: 2.08 })
  assert.deepEqual([onion.item_key, onion.qty, onion.unit, onion.unit_price_cents], ['red onion', 3.53, 'lb', 59])
  // Pack size in the name: unit recorded, qty scaled by packs, price per unit derived.
  const rice = db.parseReceiptLine({ name: 'Rice 20 lb', qty: 2, price: 30 })
  assert.deepEqual([rice.item_key, rice.qty, rice.unit, rice.unit_price_cents], ['rice', 40, 'lb', 75])
  // Plural and bare name share one key, so the same item from two receipts groups together.
  assert.equal(db.parseReceiptLine({ name: 'Bananas', price: 1 }).item_key, db.parseReceiptLine({ name: 'Banana' }).item_key)
  // Fractional count with no unit is a weight.
  assert.equal(db.parseReceiptLine({ name: 'Green pepper', qty: 0.5, price: 1 }).unit, 'lb')
})

test('price history tracks an item across receipts, and set_receipt_items replaces lines', () => {
  db.addReceipt({ merchant: 'Price Mart', purchased_at: '2026-06-01T10:00:00', total_cents: 500,
    line_items: [{ name: 'Test lentils 2 lb', qty: 1, price: 4 }] })
  db.addReceipt({ merchant: 'Price Mart', purchased_at: '2026-06-08T10:00:00', total_cents: 600,
    line_items: [{ name: 'TEST LENTILS 2 LB', qty: 1, price: 5 }] })
  const [it] = db.priceItems({ q: 'test lentil' })
  assert.equal(it.purchases, 2)
  assert.deepEqual([it.unit, it.min_cents, it.max_cents, it.last_cents, it.prev_cents, it.change_pct], ['lb', 200, 250, 250, 200, 25])
  assert.deepEqual(db.priceHistory(it.item_key).map((h) => h.unit_price_cents), [200, 250], 'oldest first')

  // Correcting the second receipt's lines must not leave the old line behind.
  const id = db.priceHistory(it.item_key)[1].receipt_id
  assert.equal(db.setReceiptItems(id, [{ name: 'Test lentils 2 lb', qty: 1, price: 4.4 }]), 1)
  assert.deepEqual(db.priceHistory(it.item_key).map((h) => h.unit_price_cents), [200, 220])
  assert.equal(db.setReceiptItems(999999, []), null, 'unknown receipt')
})
