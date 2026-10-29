const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const db = require('../server/db.cjs')
const shopping = require('../server/shopping.cjs')

// Fresh throwaway DB per run — never touch .data/finance.sqlite from tests.
const tmp = path.join(os.tmpdir(), `shopping-test-${process.pid}.sqlite`)
try { fs.unlinkSync(tmp) } catch {}
db.initDb(tmp)
process.on('exit', () => { try { fs.unlinkSync(tmp) } catch {} })

// milk: rebought after 6 days; rice: a 20 lb bag lasts a month
const buy = (at, name, price) => db.addReceipt({ merchant: 'Corner Market', purchased_at: at, total_cents: Math.round(price * 100), line_items: [{ name, price }] })
buy('2026-10-01', 'Test milk 1 gal', 3.49); buy('2026-10-07', 'Test milk 1 gal', 3.49)
buy('2026-09-01', 'Test rice 20 lb', 15.99); buy('2026-10-01', 'Test rice 20 lb', 15.99)

test('rules add low items once, and dismiss holds until new information', () => {
  assert.equal(db.refreshShoppingRules({ today: '2026-10-12' }).added, 1) // milk ~1 day left; rice in stock
  assert.equal(db.refreshShoppingRules({ today: '2026-10-12' }).added, 0, 'no duplicate')
  const [row] = db.shoppingList({ today: '2026-10-12' }).items
  db.updateShoppingList({ dismiss: [row.id] })
  assert.equal(db.refreshShoppingRules({ today: '2026-10-13' }).added, 0, 'suppressed')
  db.markUsedUp({ item_key: row.item_key, at: '2026-10-14' })
  assert.equal(db.refreshShoppingRules({ today: '2026-10-14' }).added, 1, 'new information')
})
test('a typed item merges with the rule row and a receipt closes it', () => {
  db.updateShoppingList({ add: [{ name: 'Test milk' }] })
  const open = db.shoppingList({ today: '2026-10-14' }).items.filter((r) => /milk/i.test(r.name))
  assert.equal(open.length, 1); assert.equal(open[0].source, 'user')
  db.addReceipt({ merchant: 'Corner Market', purchased_at: '2026-10-15T09:00:00', total_cents: 349, line_items: [{ name: 'Test milk 1 gal', price: 3.49 }] })
  assert.equal(db.shoppingList({ today: '2026-10-15' }).items.filter((r) => /milk/i.test(r.name)).length, 0)
})
test('a tick with no receipt counts as a restock', () => {
  db.markUsedUp({ item_key: 'test rice', at: '2026-10-15' }); db.refreshShoppingRules({ today: '2026-10-15' })
  const rice = db.shoppingList({ today: '2026-10-15' }).items.find((r) => r.item_key === 'test rice')
  db.updateShoppingList({ bought: [rice.id], today: '2026-10-15' })
  assert.equal(db.inventory({ q: 'test rice', today: '2026-10-16' })[0].status, 'in_stock')
})
test('AI cannot touch owner rows or re-add suppressed ones, and is clipped', () => {
  db.updateShoppingList({ add: [{ name: 'Test bread' }] })
  const bread = db.shoppingList({ today: '2026-10-15' }).items.find((r) => /bread/i.test(r.name))
  const r = db.applyShoppingAI({ add: [{ item_key: null, name: 'x'.repeat(500), qty: -2, reason: 'r' }, ...Array(200).fill({ item_key: null, name: 'Test soap', qty: 1, reason: 'r' })],
    update: [{ id: 999999, qty: 1, reason: 'r' }], remove: [{ id: bread.id, reason: 'r' }] })
  assert.ok(r.refused >= 2); assert.ok(db.shoppingList({ today: '2026-10-15' }).items.some((x) => x.id === bread.id))
  assert.ok(db.shoppingList({ today: '2026-10-15' }).items.every((x) => x.name.length <= 80 && (x.qty == null || x.qty > 0)))
  assert.ok(db.shoppingList({ today: '2026-10-15' }).items.length <= 45)
})
test('refresh marker and run lock', () => {
  assert.deepEqual(db.requestShoppingRefresh(), { queued: true })
  assert.equal(db.claimShoppingRun(new Date('2026-10-15T10:00:00')), true)
  assert.equal(db.claimShoppingRun(new Date('2026-10-15T10:01:00')), false)
  db.finishShoppingRun({ ok: true, message: 'ok', marker: db.shoppingChangeMarker() })
  assert.equal(db.shoppingList({ today: '2026-10-15' }).ai.pending, false)
})

// ── beyond the brief ──────────────────────────────────────────────────────────
const open = (today = '2026-10-16') => db.shoppingList({ today })

test('ruleSuggestions: used up, running low, or days_left <= 3, never lapsed / off / once', () => {
  const it = (status, days_left) => ({ item_key: `${status}${days_left}`, unit: 'each', name: 'N', status, days_left, last_qty: 2 })
  const got = shopping.ruleSuggestions([it('used_up', 0), it('running_low', null), it('running_low', 2), it('in_stock', 3), it('in_stock', 4),
    it('lapsed', 0), it('off', null), it('once', null), it('learning', null), it('in_stock', 1)])
  assert.deepEqual(got.map((x) => x.reason), ['used up', 'running low', '~2 days left', '~3 days left', '~1 day left'])
  assert.ok(got.every((x) => x.qty === 2 && x.unit === 'each' && x.name === 'N'))
})
test('re-reading an old receipt does not close a row opened since; a new receipt does', () => {
  db.updateShoppingList({ add: [{ name: 'Test rice' }] })                    // the owner may re-add a ticked item at once
  buy('2026-10-01', 'Test rice 20 lb', 15.99)                                // same receipt again (external id matches)
  assert.equal(open().items.filter((r) => r.item_key === 'test rice').length, 1)
  buy('2026-10-16', 'Test rice 20 lb', 15.99)
  assert.equal(open().items.filter((r) => r.item_key === 'test rice').length, 0)
})
test('dismiss only closes suggestions, remove only closes owner rows, and both hold off the AI', () => {
  const rows = open().items, bread = rows.find((r) => /bread/i.test(r.name)), soap = rows.find((r) => r.item_key === 'test soap')
  assert.equal(db.updateShoppingList({ dismiss: [bread.id], remove: [soap.id] }).changed, 0)
  assert.equal(db.updateShoppingList({ dismiss: [soap.id, 424242], remove: [bread.id] }).changed, 2)
  assert.deepEqual(db.applyShoppingAI({ add: [{ item_key: null, name: 'Test soap' }, { item_key: null, name: 'Test bread' }] }), { added: 0, updated: 0, removed: 0, refused: 2 })
  assert.ok(db.isSuppressed('test soap') && db.isSuppressed('test bread'))
})
test('AI may edit and remove its own rows, and the total uses the price hints', () => {
  db.updateShoppingList({ add: [{ name: 'Test milk', qty: 2 }] })
  const l = open(), milk = l.items.find((r) => r.item_key === 'test milk'), ai = l.items.find((r) => r.source === 'ai')
  assert.deepEqual([milk.last_price_cents, milk.cheapest_merchant, ai.last_price_cents, l.total_cents], [349, 'Corner Market', null, 698])
  const u = db.applyShoppingAI({ update: [{ id: ai.id, qty: 3, reason: 'new reason' }, { id: milk.id, qty: 9, reason: 'no' }] })
  assert.deepEqual([u.updated, u.refused], [1, 1])
  const after = open().items
  assert.deepEqual([after.find((r) => r.id === ai.id).qty, after.find((r) => r.id === ai.id).reason, after.find((r) => r.id === milk.id).qty], [3, 'new reason', 2])
  const d = db.applyShoppingAI({ remove: [{ id: ai.id }, { id: milk.id }] })
  assert.deepEqual([d.removed, d.refused], [1, 1])
  assert.ok(!open().items.some((r) => r.id === ai.id) && db.isSuppressed(ai.item_key))
})
test('a stale run lock is reclaimed, the outcome is reported, and the marker follows new data', () => {
  assert.equal(db.claimShoppingRun(new Date('2026-10-15T11:00:00')), true)
  assert.equal(db.claimShoppingRun(new Date('2026-10-15T11:02:01')), true)
  db.finishShoppingRun({ ok: false, message: 'boom', marker: 'm' })
  const ai = open().ai
  assert.deepEqual([ai.ok, ai.message, ai.pending, db.shoppingState().last_marker], [false, 'boom', false, 'm'])
  const before = db.shoppingChangeMarker()
  db.markUsedUp({ item_key: 'test milk', at: '2026-10-17' })
  assert.notEqual(db.shoppingChangeMarker(), before)
})
test('only a receipt newer than the close lifts the suppression, not a re-read of an old one', () => {
  buy('2026-10-16', 'Test flour 5 lb', 4.99)
  db.updateShoppingList({ add: [{ name: 'Test flour' }] })
  const flour = open().items.find((r) => r.item_key === 'test flour')
  db.updateShoppingList({ remove: [flour.id] })
  assert.equal(db.isSuppressed('test flour'), true)
  buy('2026-10-16', 'Test flour 5 lb', 4.99)                      // the same receipt again
  assert.equal(db.isSuppressed('test flour'), true)
  buy('2026-10-17', 'Test flour 5 lb', 4.99)
  assert.equal(db.isSuppressed('test flour'), false)
})
test('one AI run adds at most 40 items', () => {
  const r = db.applyShoppingAI({ add: Array.from({ length: 60 }, (_, i) => ({ item_key: null, name: `Test cap item ${i}`, qty: 1 })) })
  assert.deepEqual([r.added, r.refused], [40, 20])
})

// ── fix round 1 ───────────────────────────────────────────────────────────────
test('the change marker ignores identical re-reads and moves for a new receipt or a Used up tap', () => {
  const m = db.shoppingChangeMarker()
  buy('2026-10-01', 'Test rice 20 lb', 15.99)                     // the same old receipt, same lines
  assert.equal(db.shoppingChangeMarker(), m)
  buy('2026-10-18', 'Test rice 20 lb', 15.99)
  const m2 = db.shoppingChangeMarker()
  assert.notEqual(m2, m)
  db.markUsedUp({ item_key: 'test rice', at: '2026-10-19' })
  assert.notEqual(db.shoppingChangeMarker(), m2)
})
test('a made-up item_key cannot dodge a name the owner closed or listed', () => {
  // test soap was dismissed and test bread removed earlier, with nothing new for either since
  const closed = db.applyShoppingAI({ add: [{ item_key: 'test soap bar', name: 'Test soap' }, { item_key: 'test bread loaf', name: 'Test bread' }] })
  assert.deepEqual([closed.added, closed.refused], [0, 2])
  db.updateShoppingList({ add: [{ name: 'Test eggs' }] })
  const listed = db.applyShoppingAI({ add: [{ item_key: 'test egg', name: 'Some other wording' },    // the key is an open row (keys are singular)
                                            { item_key: 'test eggs dozen', name: 'Test eggs' }] })  // the name is an open row
  assert.deepEqual([listed.added, listed.refused], [0, 2])
})
test('the model key is stored only when receipts know it, else the name decides', () => {
  const r = db.applyShoppingAI({ add: [{ item_key: 'test flour', name: 'Flour sack' }, { item_key: 'made up', name: 'Another thing' }] })
  assert.equal(r.added, 2)
  const keys = open().items.filter((x) => /^(flour sack|another thing)$/i.test(x.name)).map((x) => x.item_key)
  assert.deepEqual(keys, ['test flour', 'another thing'])
})

// ── final review fixes ────────────────────────────────────────────────────────
const listed = (key, today) => open(today).items.some((r) => r.item_key === key)
test('bought through the list by a receipt, it comes back once it runs low again', () => {
  buy('2026-10-01', 'Test yogurt 32 oz', 2.99); buy('2026-10-07', 'Test yogurt 32 oz', 2.99)   // lasts 6 days
  db.refreshShoppingRules({ today: '2026-10-12' })
  assert.ok(listed('test yogurt', '2026-10-12'), 'suggested: ~1 day left')
  buy('2026-10-13', 'Test yogurt 32 oz', 2.99)                                                  // the receipt closes the row
  assert.ok(!listed('test yogurt', '2026-10-13'))
  db.refreshShoppingRules({ today: '2026-10-16' })
  assert.ok(!listed('test yogurt', '2026-10-16'), '3 days left is in stock: the restock still holds it back')
  db.refreshShoppingRules({ today: '2026-10-18' })
  assert.equal(db.inventory({ q: 'test yogurt', today: '2026-10-18' })[0].status, 'running_low')
  assert.ok(listed('test yogurt', '2026-10-18'), 'running low again: back on the list')
})
test('ticked bought with no receipt, it comes back once it runs low again, for the rules and the AI', () => {
  buy('2026-09-01', 'Test coffee 12 oz', 8.99); buy('2026-10-01', 'Test coffee 12 oz', 8.99)   // lasts 30 days
  db.refreshShoppingRules({ today: '2026-10-29' })
  const row = open('2026-10-29').items.find((r) => r.item_key === 'test coffee')
  db.updateShoppingList({ bought: [row.id], today: '2026-10-29' })
  db.refreshShoppingRules({ today: '2026-11-20' })
  assert.ok(!listed('test coffee', '2026-11-20'), 'restocked by the tick')
  assert.equal(db.applyShoppingAI({ add: [{ item_key: null, name: 'Test coffee' }] }, { today: '2026-11-20' }).refused, 1)
  assert.equal(db.inventory({ q: 'test coffee', today: '2026-11-27' })[0].status, 'running_low')
  assert.equal(db.applyShoppingAI({ add: [{ item_key: null, name: 'Test coffee' }] }, { today: '2026-11-27' }).added, 1)
  db.refreshShoppingRules({ today: '2026-11-27' })
  assert.equal(open('2026-11-27').items.filter((r) => r.item_key === 'test coffee').length, 1, 'once, not twice')
})
test('qty above 999 is clipped to 999', () => {
  assert.deepEqual([shopping.cleanQty(5000), shopping.cleanQty(999), shopping.cleanQty(2.5), shopping.cleanQty(0)], [999, 999, 2.5, null])
  db.applyShoppingAI({ add: [{ item_key: null, name: 'Test sugar', qty: 1e9, reason: 'r' }] })
  const sugar = open().items.find((r) => r.name === 'Test sugar')
  assert.equal(sugar.qty, 999)
  db.applyShoppingAI({ update: [{ id: sugar.id, qty: 1e6, reason: 'r' }] })
  assert.equal(open().items.find((r) => r.id === sugar.id).qty, 999)
})
