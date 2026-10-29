const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const db = require('../server/db.cjs')
const inv = require('../server/inventory.cjs')

// Fresh throwaway DB per run — never touch .data/finance.sqlite from tests.
const tmp = path.join(os.tmpdir(), `inv-test-${process.pid}.sqlite`)
try { fs.unlinkSync(tmp) } catch {}
const raw = db.initDb(tmp)
process.on('exit', () => { try { fs.unlinkSync(tmp) } catch {} })

const P = (date, qty = 1) => ({ date, qty })
test('rebuy gaps give days per unit and the current state', () => {
  const r = inv.estimateItem({ purchases: [P('2026-10-01'), P('2026-10-07'), P('2026-10-13')], usedUp: [], tracked: null, today: '2026-10-16' })
  assert.deepEqual([r.status, r.days_per_unit, r.days_left, r.used_pct, r.lasts_days, r.cycles], ['in_stock', 6, 3, 50, 6, 2])
})
test('lifespan is per unit', () => {
  const r = inv.estimateItem({ purchases: [P('2026-10-01', 2), P('2026-10-13', 1)], usedUp: [], tracked: null, today: '2026-10-16' })
  assert.equal(r.days_per_unit, 6); assert.equal(r.days_left, 3)
})
test('a Used up tap closes a cycle early and can make it running low', () => {
  const r = inv.estimateItem({ purchases: [P('2026-10-01'), P('2026-10-11')], usedUp: ['2026-10-05'], tracked: null, today: '2026-10-14' })
  assert.deepEqual([r.days_per_unit, r.days_left, r.status], [4, 1, 'running_low'])
})
test('used up after the last purchase', () => {
  const r = inv.estimateItem({ purchases: [P('2026-10-01'), P('2026-10-07')], usedUp: ['2026-10-10'], tracked: null, today: '2026-10-12' })
  assert.deepEqual([r.status, r.qty_left], ['used_up', 0])
})
test('lapsed only past 3x life and 30 days', () => {
  const base = { purchases: [P('2026-10-01'), P('2026-10-07')], usedUp: [], tracked: null }
  assert.equal(inv.estimateItem({ ...base, today: '2026-11-20' }).status, 'lapsed')
  assert.equal(inv.estimateItem({ ...base, today: '2026-10-30' }).status, 'running_low')
})
test('tracking rule and overrides', () => {
  assert.equal(inv.estimateItem({ purchases: [P('2026-10-01')], usedUp: [], tracked: null, today: '2026-10-02' }).status, 'once')
  assert.equal(inv.estimateItem({ purchases: [P('2026-10-01')], usedUp: [], tracked: 1, today: '2026-10-02' }).status, 'learning')
  assert.equal(inv.estimateItem({ purchases: [P('2026-10-01'), P('2026-10-07')], usedUp: [], tracked: 0, today: '2026-10-08' }).status, 'off')
})
test('same-day purchases merge; zero qty counts as one; times are local days', () => {
  const r = inv.estimateItem({ purchases: [P('2026-10-01T09:00:00', 0), P('2026-10-01T18:30:00', 1), P('2026-10-05T23:59:00', 1)], usedUp: [], tracked: null, today: '2026-10-06' })
  assert.deepEqual([r.cycles, r.days_per_unit], [1, 2])
})
test('non-product lines never count', () => {
  assert.equal(inv.isProductLine('Sales tax', 120), false)
  assert.equal(inv.isProductLine('Coupon', -100), false)
  assert.equal(inv.isProductLine('Bag fee', 10), false)
  assert.equal(inv.isProductLine('Milk 1 gal', 349), true)
})
test('inventory from receipts, mark_used_up and tracking', () => {
  for (const d of ['2026-10-01', '2026-10-07']) db.addReceipt({ merchant: 'Corner Market', purchased_at: `${d}T10:00:00`, total_cents: 349, line_items: [{ name: 'Test oat milk 1 gal', price: 3.49 }, { name: 'Sales tax', price: 0.2 }] })
  const [it] = db.inventory({ q: 'test oat milk', today: '2026-10-10' })
  assert.equal(it.status, 'in_stock'); assert.equal(it.cheapest_merchant, 'Corner Market')
  assert.equal(db.inventory({ q: 'sales tax', include_untracked: true, today: '2026-10-10' }).length, 0)
  db.markUsedUp({ item_key: it.item_key, at: '2026-10-11' }); db.markUsedUp({ item_key: it.item_key, at: '2026-10-11' })
  assert.equal(db.inventory({ q: 'test oat milk', today: '2026-10-12' })[0].status, 'used_up')
  assert.throws(() => db.markUsedUp({ item_key: 'never bought', at: '2026-10-11' }), /no purchases of never bought/)
  db.setItemTracking({ item_key: it.item_key, unit: it.unit, tracked: 0 })
  assert.equal(db.inventory({ q: 'test oat milk', today: '2026-10-12' }).length, 0)
  assert.equal(db.inventory({ q: 'test oat milk', include_untracked: true, today: '2026-10-12' })[0].status, 'off')
})

// Decisions beyond the plan's tests: same-day Used up, every field present, ticked-bought restocks.
test('a Used up on a purchase day closes the cycle before that purchase', () => {
  const r = inv.estimateItem({ purchases: [P('2026-10-01'), P('2026-10-07')], usedUp: ['2026-10-07'], tracked: null, today: '2026-10-08' })
  assert.deepEqual([r.status, r.days_per_unit], ['in_stock', 6])
})
test('lapsed counts from the last Used up, and every field is always present', () => {
  const base = { purchases: [P('2026-10-01'), P('2026-10-07')], usedUp: ['2026-10-20'], tracked: null }
  assert.equal(inv.estimateItem({ ...base, today: '2026-11-10' }).status, 'used_up')
  assert.equal(inv.estimateItem({ ...base, today: '2026-11-25' }).status, 'lapsed')
  const once = inv.estimateItem({ purchases: [P('2026-10-01')], usedUp: [], tracked: null, today: '2026-10-02' })
  assert.deepEqual(Object.keys(once).sort(), ['cycles', 'days_left', 'days_per_unit', 'last_bought', 'last_qty', 'lasts_days', 'qty_left', 'status', 'used_pct'])
  assert.deepEqual([once.last_bought, once.last_qty, once.used_pct, once.cycles], ['2026-10-01', 1, null, 0])
})
test('a ticked-bought row restocks the item unless a receipt already covers that day', () => {
  for (const d of ['2026-10-01', '2026-10-07']) db.addReceipt({ merchant: 'Corner Market', purchased_at: `${d}T10:00:00`, total_cents: 499, line_items: [{ name: 'Test eggs 12 ct', price: 4.99 }] })
  const eggs = () => db.inventory({ q: 'test eggs', today: '2026-10-13' })[0]
  assert.deepEqual([eggs().status, eggs().last_bought], ['running_low', '2026-10-07'])
  const tick = raw.prepare("INSERT INTO shopping_list (item_key, name, source, status, restock_date) VALUES ('test egg', 'Test eggs', 'user', 'bought', ?)")
  tick.run('2026-10-07')   // same day as a receipt: ignored
  assert.equal(eggs().last_bought, '2026-10-07')
  tick.run('2026-10-12')
  assert.deepEqual([eggs().status, eggs().last_bought, eggs().cycles], ['in_stock', '2026-10-12', 2])
})
test('Used up and tracking writes are audited once', () => {
  const tools = db.listAudit(100).map((a) => a.tool)
  assert.equal(tools.filter((t) => t === 'mark_used_up').length, 1)   // the repeat was a no-op
  assert.equal(tools.filter((t) => t === 'set_item_tracking').length, 1)
})
