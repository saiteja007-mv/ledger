const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { render, toStoredLine } = require('../server/bill.cjs')
const db = require('../server/db.cjs')

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'bill-test-'))
db.initDb(path.join(tmp, 'finance.sqlite'))
// Windows can't delete the SQLite file while it's open; a temp dir left behind there is harmless.
test.after(() => { try { fs.rmSync(tmp, { recursive: true, force: true }) } catch {} })

const READ = {   // shape bill.extract() returns
  is_receipt: true, merchant: 'Corner Market', purchased_at: '2026-10-04T10:41:55', payment: 'VISA ****4',
  line_items: [{ name: 'BANANA DOLE', qty: 2.66, unit: 'lb', unit_price: 0.69, price: 1.84 },
    { name: 'CILANTRO', qty: 2, unit: 'EA', unit_price: 0.59, price: 1.18 }, { name: '$1 OFF REWARD', price: -1 }],
  subtotal: 2.02, tax: 0.12, total: 2.14, notes: null,
}

test('weighed lines use the stored "— qty unit @ price" convention; counts keep qty', () => {
  assert.deepEqual(toStoredLine(READ.line_items[0]), { name: 'BANANA DOLE — 2.66 lb @ $0.69/lb', qty: 1, price: 1.84 })
  assert.deepEqual(toStoredLine(READ.line_items[1]), { name: 'CILANTRO', qty: 2, price: 1.18 })
  assert.equal(db.parseReceiptLine(toStoredLine(READ.line_items[0])).unit_price_cents, 69)
})

test('applyBill fills only blanks, itemises once, and the bill checks its own arithmetic', () => {
  const a = db.addReceipt({ external_id: 'img:a.jpg', image_path: 'a.jpg', source: 'web' })
  const filled = db.applyBill(a.id, READ)
  assert.equal(filled.merchant, 'Corner Market')
  assert.equal(filled.total_cents, 214)
  assert.equal(filled.tax_cents, 12)
  assert.equal(filled.line_items.length, 3)
  assert.equal(filled.bill_status, 'done')
  assert.match(render(filled), /✓ items \+ tax match the total/)

  // the same purchase uploaded again as a split share: typed values win, items aren't doubled
  const b = db.addReceipt({ merchant: 'Corner Market for Alex', purchased_at: '2026-10-04T12:00:00', total_cents: 107,
    image_path: 'b.jpg', source: 'web' })
  const share = db.applyBill(b.id, READ)
  assert.equal(share.merchant, 'Corner Market for Alex')
  assert.equal(share.total_cents, 107)
  assert.equal(share.tax_cents, null)          // printed tax belongs to the printed total
  assert.equal(share.line_items, null)
  assert.equal(share.bill_data.total, 2.14)
  const svg = render(share)
  assert.match(svg, /CORNER MARKET/)      // the bill shows the paper, not the ledger label
  assert.match(svg, /BANANA DOLE/)
})

test('render escapes everything read off the photo and flags totals that do not add up', () => {
  const svg = render({ id: 9, merchant: null, line_items: null, transaction: null,
    bill_data: { ...READ, merchant: '<script>alert(1)</script>', total: 9.99 } })
  assert.doesNotMatch(svg, /<script>/)
  assert.match(svg, /&lt;SCRIPT&gt;/)
  assert.match(svg, /check the photo/)
})
