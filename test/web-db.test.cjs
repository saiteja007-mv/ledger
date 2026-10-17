// Covers the query + edit surface added for the web UI. Same discipline as db.test.cjs:
// a throwaway DB per run, never .data/finance.sqlite.
const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const db = require('../server/db.cjs')

const tmp = path.join(os.tmpdir(), `finance-web-test-${process.pid}.sqlite`)
try { fs.unlinkSync(tmp) } catch {}
db.initDb(tmp)
process.on('exit', () => { try { fs.unlinkSync(tmp) } catch {} })

const rows = [
  { account: 'Cash', posted_at: '2026-06-02T09:00:00', direction: 'expense', amount_cents: 1500, merchant: 'Uber ride', category: '🚖 Transport', reviewed: 1 },
  { account: 'Cash', posted_at: '2026-06-11T12:00:00', direction: 'expense', amount_cents: 2500, merchant: 'Chipotle', category: '🍜 Food', reviewed: 1 },
  { account: 'Checking', posted_at: '2026-07-03T08:00:00', direction: 'income', amount_cents: 900000, reviewed: 1 },
  { account: 'Checking', posted_at: '2026-07-09T16:30:00', direction: 'expense', amount_cents: 4200, merchant: 'Costco' },      // uncategorized, unreviewed
  { account: 'Checking', posted_at: '2026-07-20T10:00:00', direction: 'transfer_out', amount_cents: 30000, reviewed: 1 },
]
db.upsertTransactions(rows, { source: 'test' })

test('filters compose, and count agrees with the page', () => {
  const f = { account: 'Checking', direction: 'expense' }
  assert.equal(db.countTransactions(f), 1)
  assert.equal(db.listTransactions({ ...f, limit: 50 }).length, 1)
  assert.equal(db.countTransactions({ from: '2026-07-01', to: '2026-08-01' }), 3)
})

test('offset pages without dropping or repeating a row', () => {
  const all = db.listTransactions({ limit: 100 })
  assert.equal(all.length, 5)
  const p1 = db.listTransactions({ limit: 2, offset: 0 })
  const p2 = db.listTransactions({ limit: 2, offset: 2 })
  const p3 = db.listTransactions({ limit: 2, offset: 4 })
  const paged = [...p1, ...p2, ...p3].map((r) => r.id)
  assert.deepEqual(paged, all.map((r) => r.id), 'paging must reproduce the full ordered list')
  assert.equal(new Set(paged).size, 5, 'no row may appear on two pages')
})

test('free-text search spans merchant and category', () => {
  assert.equal(db.countTransactions({ q: 'Uber' }), 1)
  assert.equal(db.countTransactions({ q: 'Food' }), 1)
  assert.equal(db.countTransactions({ q: 'nothing-matches-this' }), 0)
})

test('(uncategorized) selects NULL, not the literal string', () => {
  // The UI sends a display label; matching it with `category = '(uncategorized)'` would
  // return nothing and quietly hide the rows that most need attention.
  const un = db.listTransactions({ category: '(uncategorized)', limit: 10 })
  assert.equal(un.length, 3, 'the income, Costco and transfer rows all lack a category')
  assert.equal(db.countTransactions({ category: '(uncategorized)' }), 3, 'count must agree with the page')
  assert.ok(un.every((r) => r.category === null))
  assert.ok(un.some((r) => r.merchant === 'Costco'))
})

test('reviewed filter isolates the queue', () => {
  assert.equal(db.countTransactions({ reviewed: 0 }), 1)
  assert.equal(db.countTransactions({ reviewed: 1 }), 4)
})

test('voided rows leave the default view but survive include_voided', () => {
  const target = db.listTransactions({ q: 'Chipotle', limit: 1 })[0]
  db.voidTransaction(target.id, 'test')
  assert.equal(db.countTransactions({ q: 'Chipotle' }), 0)
  assert.equal(db.countTransactions({ q: 'Chipotle', include_voided: true }), 1)
})

// Placed directly after the void test and before any further inserts: it asserts on
// exact monthly sums, so a row added later would silently invalidate it.
test('monthlySeries buckets by month, oldest first, excluding transfers', () => {
  const s = db.monthlySeries({ months: 12 })
  assert.deepEqual(s.map((r) => r.month), ['2026-06', '2026-07'], 'oldest first')

  const jul = s.find((r) => r.month === '2026-07')
  assert.equal(jul.income_cents, 900000)
  assert.equal(jul.expense_cents, 4200)
  // The 30000 transfer_out must not appear as spend.
  assert.equal(jul.expense_cents + jul.income_cents, 904200)

  const jun = s.find((r) => r.month === '2026-06')
  assert.equal(jun.expense_cents, 1500, 'the voided Chipotle row is excluded')
})

test('updateTransaction edits only non-key fields', () => {
  const t = db.listTransactions({ q: 'Uber', limit: 1 })[0]
  const before = { amount: t.amount_cents, posted: t.posted_at, ext: t.external_id }

  const after = db.updateTransaction(t.id, { merchant: 'Lyft ride', note: 'corrected' })
  assert.equal(after.merchant, 'Lyft ride')
  assert.equal(after.note, 'corrected')

  // The natural key must be untouched — otherwise the row orphans from every future re-sync.
  assert.equal(after.amount_cents, before.amount)
  assert.equal(after.posted_at, before.posted)
  assert.equal(after.external_id, before.ext)

  // Key fields are silently ignored rather than applied.
  const ignored = db.updateTransaction(t.id, { merchant: 'X', amount_cents: 999999, posted_at: '1999-01-01T00:00:00' })
  assert.equal(ignored.amount_cents, before.amount, 'amount must not be writable')
  assert.equal(ignored.posted_at, before.posted, 'posted_at must not be writable')

  assert.throws(() => db.updateTransaction(t.id, { amount_cents: 1 }), /editable fields/,
    'an update with no editable field is an error, not a silent no-op')
})

test('empty string clears a field to NULL rather than storing ""', () => {
  // Self-contained: the row above has already been renamed by the previous test.
  db.upsertTransactions([{ account: 'Cash', posted_at: '2026-06-15T09:00:00', direction: 'expense',
    amount_cents: 700, merchant: 'Clearable', note: 'delete me', reviewed: 1 }], { source: 'test' })
  const t = db.listTransactions({ q: 'Clearable', limit: 1 })[0]
  assert.equal(t.note, 'delete me')
  assert.equal(db.updateTransaction(t.id, { note: '' }).note, null, 'blanking a field stores NULL, not ""')
})

test('categoryStats rolls up every direction and counts uncategorized rows', () => {
  const s = db.categoryStats()
  const byName = Object.fromEntries(s.map((r) => [r.category, r]))

  assert.ok(byName['(uncategorized)'], 'NULL categories are grouped under a label, not dropped')
  // income + Costco + transfer + the Clearable row added above.
  assert.equal(byName['(uncategorized)'].n, 4)
  assert.equal(byName['🚖 Transport'].expense_cents, 1500)
  // Income lands in its own column rather than inflating spend, and the 30000 transfer
  // counts toward neither.
  assert.equal(byName['(uncategorized)'].income_cents, 900000)
  assert.equal(byName['(uncategorized)'].expense_cents, 4900)
  assert.ok(!byName['🍜 Food'], 'the voided row leaves its category behind entirely')
})

test('renameCategory moves a whole category, and handles the uncategorized label', () => {
  const before = db.countTransactions({ category: '(uncategorized)' })
  assert.equal(before, 4)

  // '(uncategorized)' is a display label, not a stored value — it must map back to NULL.
  const r = db.renameCategory('(uncategorized)', '🛒 Groceries')
  assert.equal(r.renamed, before)
  assert.equal(db.countTransactions({ category: '(uncategorized)' }), 0)
  assert.equal(db.countTransactions({ category: '🛒 Groceries' }), before)

  db.renameCategory('🛒 Groceries', '🥕 Produce')
  assert.equal(db.countTransactions({ category: '🥕 Produce' }), before)
  assert.equal(db.countTransactions({ category: '🛒 Groceries' }), 0)
})

test('re-adding a receipt with a new photo updates the image instead of keeping the old one', () => {
  // The natural key is merchant|purchased_at|total, so retaking the photo for the same
  // purchase collides. The image must follow; a null must not wipe an existing one.
  const key = { merchant: 'Retake Test', purchased_at: '2026-07-09T16:00:00', total_cents: 999 }
  db.addReceipt({ ...key, image_path: 'aaa.jpg' })
  const id = db.listReceipts({ limit: 50 }).find((r) => r.merchant === 'Retake Test').id
  assert.equal(db.getReceipt(id).image_path, 'aaa.jpg')

  db.addReceipt({ ...key, image_path: 'bbb.jpg' })
  assert.equal(db.getReceipt(id).image_path, 'bbb.jpg', 'a new photo replaces the old one')

  db.addReceipt({ ...key })
  assert.equal(db.getReceipt(id).image_path, 'bbb.jpg', 'sending no image must not wipe it')
})

test('upsert returns the row id so a receipt can attach to what was just created', () => {
  const r = db.upsertTransactions([{ account: 'Cash', posted_at: '2026-07-25T13:00:00',
    direction: 'expense', amount_cents: 3300, merchant: 'New Row', reviewed: 1 }], { source: 'test' })
  assert.equal(r.ids.length, 1)
  assert.ok(Number.isInteger(r.ids[0]))
  assert.equal(db.getTransaction(r.ids[0]).merchant, 'New Row')

  // Re-sending the same row is an update, and must report the SAME id — otherwise the
  // add-with-photo flow would attach the receipt to a row that does not exist.
  const again = db.upsertTransactions([{ account: 'Cash', posted_at: '2026-07-25T13:00:00',
    direction: 'expense', amount_cents: 3300, merchant: 'New Row', reviewed: 1 }], { source: 'test' })
  assert.equal(again.inserted, 0)
  assert.deepEqual(again.ids, r.ids)
})

test('receiptImageFile only resolves content-hash names that exist on disk', () => {
  const dir = db.receiptDir()
  fs.mkdirSync(dir, { recursive: true })
  const name = 'a'.repeat(64) + '.png'
  fs.writeFileSync(path.join(dir, name), Buffer.from([1, 2, 3]))
  process.on('exit', () => { try { fs.unlinkSync(path.join(dir, name)) } catch {} })

  assert.ok(db.receiptImageFile(name), 'a real content-hash file resolves')
  assert.equal(db.receiptImageFile('b'.repeat(64) + '.png'), null, 'missing file returns null')
  assert.equal(db.receiptImageFile(null), null)
  // Nothing user-supplied may reach the filesystem.
  for (const bad of ['../../server/db.cjs', '/etc/passwd', 'a'.repeat(64) + '.sh', 'notahash.png']) {
    assert.equal(db.receiptImageFile(bad), null, `${bad} must not resolve`)
  }
})

test('receiptDir follows the open database, not the default path', () => {
  assert.equal(db.receiptDir(), path.join(path.dirname(tmp), 'receipts'))
  assert.ok(!db.receiptDir().includes('finance-mcp/.data'), 'a test run must not point at real data')
})

test('receipt attach round-trips and getTransaction resolves the account name', () => {
  const t = db.listTransactions({ q: 'Costco', limit: 1 })[0]
  const { external_id } = db.addReceipt({ merchant: 'Costco', purchased_at: '2026-07-09T16:00:00', total_cents: 4200 })
  const r = db.listReceipts({ limit: 50 }).find((x) => x.external_id === external_id)

  // Assert on this receipt specifically — earlier tests leave other unattached receipts
  // behind, so a global count would couple this test to their bookkeeping.
  assert.equal(r.transaction_id, null)
  db.attachReceipt(r.id, t.id)
  assert.equal(db.getReceipt(r.id).transaction_id, t.id)
  assert.deepEqual(db.receiptsForTransaction(t.id).map((x) => x.id), [r.id])

  assert.equal(db.getTransaction(t.id).account, 'Checking')
  assert.equal(db.getTransaction(999999), null)

  db.attachReceipt(r.id, null)
  assert.equal(db.receiptsForTransaction(t.id).length, 0, 'detach must be reversible')
  assert.equal(db.getReceipt(r.id).transaction_id, null)
})
