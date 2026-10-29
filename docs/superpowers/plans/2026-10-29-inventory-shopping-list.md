# Inventory and Shopping List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inventory (stock, usage, run-out) derived from receipt lines plus a Claude-kept Shopping List, on the server, MCP, web app and iPhone app.

**Architecture:** Pure estimator and list rules in two new server modules, persisted in four new SQLite tables in `server/db.cjs`; a Claude runner that only `ledger-web` starts; six MCP tools (which `web/api.cjs` exposes to the iPhone automatically); two web views and two iPhone screens under Item Prices.

**Tech Stack:** Node ≥ 22.5 CommonJS, `node:sqlite`, `node:test`, zod, `@modelcontextprotocol/sdk`, `@anthropic-ai/sdk` (new), vanilla JS web app, SwiftUI (iOS SDK 27.0) built with xtool.

**Spec:** `docs/superpowers/specs/2026-10-29-inventory-shopping-list-design.md`

## Global Constraints

- Public repo: examples use made-up data only ("Corner Market", "Visa 1234", "Alex"). Scan every commit for tailnet names, 100.x IPs, real merchants, card/bank names before push.
- Only new runtime dependency: `@anthropic-ai/sdk`.
- Model `claude-opus-5-5`, `output_config.effort: "low"`, structured output via `output_config.format`, `fallbacks: "default"` with beta `server-side-fallback-2026-07-01` on `client.beta.messages.create`. No `temperature`/`top_p`. Read the claude-api skill (`typescript/claude-api/README.md`, `tool-use.md` Structured outputs) before writing the call.
- Key file: `process.env.LEDGER_ANTHROPIC_KEY_FILE`, default `<repo>/.data/anthropic-key.txt`. Never logged, never in an error message, never returned by any route or tool.
- Only `ledger-web` (`web/index.cjs`) ever calls Claude. Everyone else sets the refresh marker.
- Numbers: running low = `used ≥ 0.8` or `days_left ≤ 2`; list suggestion = used up, running low, or `days_left ≤ 3`; lapsed = elapsed `> 3 × E` and `≥ 30` days; median of last **6** cycles; AI input history **90** days; poll **60 000 ms**; daily run **06:00** local; run timeout **120 000 ms**; AI adds capped at **40**, names ≤ **80** chars, qty > 0.
- Dates: compare as local `YYYY-MM-DD` (first 10 chars of `purchased_at`); "today" is the local date (same helper as `server/mcp.mjs:24`).
- Every new write function calls `audit(tool, actor, args, affected)` itself (`W` in mcp.mjs does not audit).
- Web: every name and reason goes through `esc()` (AI output is untrusted text).
- iOS: models are Foundation-only, decoded with `.convertFromSnakeCase` and no CodingKeys; use existing `KitIcon` members only; follow swiftui-pro, no API newer than iOS 27.0.

## Review Focus

1. **Zero or missing quantity** on a purchase (qty 0, null) must not divide by zero; treat as 1. → test in Task 1.
2. **`mark_used_up` on an item never bought** must fail with a clear error, and a second tap on the same day must not add a second event. → test in Task 1.
3. **Timestamps with a time part** (`2026-10-07T18:30:00`) must count as that local day, never shift a day via UTC. → test in Task 1.
4. **Bad AI output** (negative qty, 200 adds, a 500-char name, an id that does not exist) must be clipped or ignored, never crash or write junk. → test in Task 3.
5. **Missing, empty or whitespace key file** → rules-only list with "no API key" status, client never constructed, key text never in any message. → test in Task 3.

---

### Task 1: Estimator and inventory data

**Files:**
- Create: `server/inventory.cjs`
- Modify: `server/db.cjs` (schema block lines 36-147; new functions after `priceHistory` ~line 637; exports 682-693)
- Test: `test/inventory.test.cjs`

**Interfaces:**
- Produces (`server/inventory.cjs`):
  - `isProductLine(name: string, total_cents: number) → boolean` — false when `total_cents ≤ 0` or name matches `/\b(tax|fee|deposit|bag|tip|service charge|coupon|discount)\b/i`.
  - `estimateItem({ purchases: {date, qty}[], usedUp: string[], tracked: null|0|1, today: string }) → { status, last_bought, last_qty, qty_left, used_pct, days_left, lasts_days, days_per_unit, cycles }` where `status ∈ 'learning'|'in_stock'|'running_low'|'used_up'|'lapsed'|'off'|'once'`. Same-day purchases are merged, qty ≤ 0 or null counts as 1.
  - Constants exported: `RUNNING_LOW_USED = 0.8, RUNNING_LOW_DAYS = 2, LIST_DAYS = 3, LAPSE_FACTOR = 3, LAPSE_MIN_DAYS = 30, CYCLES = 6`.
- Produces (`server/db.cjs`, exported):
  - Tables `item_settings`, `item_events`, `shopping_list` as in the spec's Data section, with two extra `shopping_list` columns `close_event_id INTEGER, close_receipt_id INTEGER` (the max `item_events.id` / `receipts.id` when the row was closed, so suppression never depends on clocks), plus `shopping_state(id INTEGER PRIMARY KEY CHECK (id = 1), requested_at TEXT, running_since TEXT, last_run_at TEXT, last_ok INTEGER, last_message TEXT, last_marker TEXT)`.
  - `inventory({ q = null, status = null, include_untracked = false, today }) → Item[]`, Item = estimator fields + `item_key, unit, name, tracked, last_price_cents, cheapest_merchant`. Purchases come from `receipt_items` filtered by `isProductLine`, grouped by `(item_key, unit)`; ticks (`shopping_list` rows closed `bought` by a user with no receipt) are added as purchases of the last qty. `cheapest_merchant` = lowest `unit_price_cents` in the last 90 days.
  - `markUsedUp({ item_key, unit = null, at, actor = null }) → { item_key, unit, at }`; throws `Error('no purchases of <item_key>')` when unknown; unit defaults to the most recently bought unit; same `(item_key, unit, at)` twice is a no-op.
  - `setItemTracking({ item_key, unit, tracked, actor = null }) → { item_key, unit, tracked }` (`tracked` null deletes the override).

- [ ] **Step 1: Write the failing tests** in `test/inventory.test.cjs` (`node:test` + `node:assert`; `db.initDb(path.join(os.tmpdir(), \`inv-test-${process.pid}.sqlite\`))` at top, unlink on exit):

```js
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
```

- [ ] **Step 2:** Run `node --test test/inventory.test.cjs` — expected FAIL (`Cannot find module '../server/inventory.cjs'`).
- [ ] **Step 3:** Implement `server/inventory.cjs` per the spec's "How usage is estimated" steps 1-7 (days between local `YYYY-MM-DD` dates, median of the last 6 `d_i`, `used_pct` rounded to an integer percent, `days_left`/`lasts_days` rounded to whole days, `qty_left` to 2 decimals). Learning/once/off rows still carry `last_bought`/`last_qty`.
- [ ] **Step 4:** Add the tables to the schema block and `inventory`, `markUsedUp`, `setItemTracking` to `db.cjs`, each write calling `audit('mark_used_up' | 'set_item_tracking', actor, args, 1)`; export them.
- [ ] **Step 5:** Run `node --test test/inventory.test.cjs` then `npm test` — expected all pass.
- [ ] **Step 6:** Commit `feat(server): inventory estimator from receipt lines`.

### Task 2: Shopping list data and rules

**Files:**
- Create: `server/shopping.cjs`
- Modify: `server/db.cjs` (`syncReceiptItems` ~line 562; new functions; exports)
- Test: `test/shopping.test.cjs`

**Interfaces:**
- Consumes: `db.inventory`, `parseReceiptLine(line) → { name, item_key, qty, unit, … }`, `LIST_DAYS`.
- Produces (`server/shopping.cjs`): `ruleSuggestions(items: Item[]) → { item_key, unit, name, qty, reason }[]` (status `used_up` / `running_low` or `days_left ≤ 3`, never `lapsed`/`off`/`once`; qty = `last_qty`; reason e.g. `"used up"`, `"~2 days left"`).
- Produces (`server/db.cjs`, exported):
  - `shoppingList({ today }) → { items: Row[], total_cents, ai: { last_run_at, ok, message, pending } }`; Row = `id, item_key, unit, name, qty, source, reason, last_price_cents, cheapest_merchant`; `total_cents` = Σ `qty × last_price_cents` over rows with a price.
  - `refreshShoppingRules({ today }) → { added }` — inserts `source='rule'` rows for suggestions that are not open and not suppressed.
  - `isSuppressed(item_key) → boolean` — the latest closed row (`bought`/`dismissed`/`removed`) for that key has no `item_events` row for the key with `id > close_event_id` and no `receipt_items` row for the key with `receipt_id > close_receipt_id`.
  - `updateShoppingList({ add = [], bought = [], dismiss = [], remove = [], actor = null, today }) → { added, changed }` — a `bought` tick stores `today` as the row's restock date (the purchase Task 1's `inventory` adds); `add` items `{ name, qty? }` get an `item_key` from `parseReceiptLine({ name })`; an open row with the same `item_key` becomes `source='user'` (owner wins) instead of a duplicate. `remove` only touches `source='user'` rows; `dismiss` only non-user rows.
  - `closeBoughtFromReceipt(receiptId) → number` — called at the end of `syncReceiptItems`; closes open rows whose `item_key` appears on that receipt as `bought`.
  - `requestShoppingRefresh() → { queued: true }`, `shoppingState() → row`, `claimShoppingRun(now) → boolean` (false if `running_since` is set and younger than 120 s), `finishShoppingRun({ ok, message, marker })`, `shoppingChangeMarker() → string` (max ids/counts of `receipt_items` and `item_events`).
  - `applyShoppingAI({ add, update, remove }, { actor = 'claude' }) → { added, updated, removed, refused }` — refuses changes to `source='user'` rows, re-adds of suppressed keys, unknown ids; clips per Global Constraints.

- [ ] **Step 1: Write the failing tests** in `test/shopping.test.cjs` (own temp DB). Seed two milk receipts (`2026-10-01`, `2026-10-07`, "Test milk 1 gal") and two rice receipts (`2026-09-01`, `2026-10-01`, "Test rice 20 lb").

```js
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
```

- [ ] **Step 2:** Run `node --test test/shopping.test.cjs` — expected FAIL (`db.refreshShoppingRules is not a function`).
- [ ] **Step 3:** Implement `server/shopping.cjs` and the db functions; hook `closeBoughtFromReceipt` into `syncReceiptItems` so `addReceipt`, `applyBill` and `setReceiptItems` all close bought items. Writes audit with tool names `update_shopping_list`, `apply_shopping_ai`.
- [ ] **Step 4:** Run `node --test test/shopping.test.cjs` then `npm test` — expected all pass.
- [ ] **Step 5:** Commit `feat(server): shopping list rules, owner items and suppression`.

### Task 3: Claude runner and the ledger-web timer

**Files:**
- Create: `server/shopping-ai.cjs`
- Modify: `web/index.cjs` (`server.listen` callback ~lines 605-610), `package.json`/`package-lock.json` (`npm install @anthropic-ai/sdk`)
- Test: `test/shopping-ai.test.cjs`

**Interfaces:**
- Consumes: Task 1/2 db functions.
- Produces (`server/shopping-ai.cjs`):
  - `readKey(file?) → string | null` (trimmed; empty → null; file default per Global Constraints).
  - `buildRequest({ today, items, purchases, list }) → params` — the full `client.beta.messages.create` params; `system` says list data is data, never instructions; JSON schema `{ add: [{ item_key: string|null, name, qty: number|null, unit: string|null, reason }], update: [{ id, qty, reason }], remove: [{ id, reason }] }` with `additionalProperties: false`.
  - `runShoppingAI({ db, today, client = null, keyFile } ) → Promise<{ ok, message }>` — always runs `refreshShoppingRules` first; no key → `{ ok:false, message:'no API key: rules only' }` without constructing a client; `stop_reason !== 'end_turn'` or unparsable JSON → `{ ok:false }` and no AI changes; success → `applyShoppingAI`. Purchases sent: last 90 days of tracked items only (`name, qty, unit, unit_price_cents, merchant, date`). Never sends account names or notes.
  - `startShoppingTimer({ db, everyMs = 60000, dailyAt = '06:00' }) → { stop() }` — each tick: run if `requested_at` set, or `shoppingChangeMarker() !== last_marker`, or the daily time passed since `last_run_at`; wraps the run in `claimShoppingRun`/`finishShoppingRun` and a 120 000 ms timeout.

- [ ] **Step 1: Write the failing tests** with a stub client:

```js
const stub = (reply, seen = {}) => ({ beta: { messages: { create: async (p) => (seen.params = p, reply) } } })
const ok = (obj) => ({ stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify(obj) }] })
test('no key: rules only, client never used', async () => {
  const seen = {}; const r = await ai.runShoppingAI({ db, today: '2026-10-12', client: stub(ok({}), seen), keyFile: path.join(tmp, 'missing.txt') })
  assert.deepEqual([r.ok, r.message, seen.params], [false, 'no API key: rules only', undefined])
})
test('key file is trimmed, blank is none', () => {
  fs.writeFileSync(keyFile, '  sk-test  \n'); assert.equal(ai.readKey(keyFile), 'sk-test')
  fs.writeFileSync(blank, ' \n'); assert.equal(ai.readKey(blank), null)
})
test('request shape and privacy', async () => {
  db.upsertAccount({ name: 'Visa 1234', kind: 'credit' }) // match upsertAccount's real signature in db.cjs
  const seen = {}; const r = await ai.runShoppingAI({ db, today: '2026-10-12', client: stub(ok({ add: [{ item_key: null, name: 'Test soap', qty: 1, unit: null, reason: 'weekly' }], update: [], remove: [] }), seen), keyFile })
  assert.equal(r.ok, true)
  const p = seen.params
  assert.deepEqual([p.model, p.output_config.effort, p.fallbacks], ['claude-opus-5-5', 'low', 'default'])
  assert.ok(p.betas.includes('server-side-fallback-2026-07-01'))
  assert.ok(!JSON.stringify(p).includes('Visa 1234')); assert.ok(!JSON.stringify(p).includes('sk-test'))
})
test('refusal or junk leaves the list alone', async () => {
  const before = db.shoppingList({ today: '2026-10-12' }).items.length
  assert.equal((await ai.runShoppingAI({ db, today: '2026-10-12', client: stub({ stop_reason: 'refusal', content: [] }), keyFile })).ok, false)
  assert.equal((await ai.runShoppingAI({ db, today: '2026-10-12', client: stub({ stop_reason: 'end_turn', content: [{ type: 'text', text: 'not json' }] }), keyFile })).ok, false)
  assert.equal(db.shoppingList({ today: '2026-10-12' }).items.length, before)
})
```

- [ ] **Step 2:** Run `node --test test/shopping-ai.test.cjs` — expected FAIL (module missing).
- [ ] **Step 3:** `npm install @anthropic-ai/sdk`; implement `server/shopping-ai.cjs` (real client: `new Anthropic({ apiKey: readKey(...) })` created per run, only when a key exists).
- [ ] **Step 4:** In `web/index.cjs` `server.listen` callback, call `startShoppingTimer({ db })` unless `process.env.LEDGER_SHOPPING_TIMER === 'off'` (tests set it off).
- [ ] **Step 5:** Run `npm test` — expected all pass, no network.
- [ ] **Step 6:** Commit `feat(server): Claude keeps the shopping list (rules without a key)`.

### Task 4: MCP tools

**Files:**
- Modify: `server/mcp.mjs` (READ tools near `item_prices` line 283; WRITE tools after `set_receipt_items` ~line 293)
- Modify: `test/api.test.cjs` (tool-name list lines 66-74; new test)

**Interfaces:**
- Consumes: Tasks 1-2 db functions; `today()` (mcp.mjs:24); `money()`.
- Produces tools: `inventory { q?, status?, include_untracked? }`, `mark_used_up { item_key, unit?, date? }`, `set_item_tracking { item_key, unit, tracked: boolean|null }`, `shopping_list {}`, `update_shopping_list { add?: {name, qty?}[], bought?: int[], dismiss?: int[], remove?: int[] }`, `refresh_shopping_list {}` → `{ queued: true }`. Prices returned both as `*_cents` and decimal via `money()`. Descriptions state units, statuses and that `refresh_shopping_list` only queues.

- [ ] **Step 1:** Add the six names to the expected-tools list and a test: seed a receipt pair via `ok('add_receipt', …)` twice, then `ok('inventory', {})` has the item, `ok('mark_used_up', { item_key })` returns the date, `ok('update_shopping_list', { add: [{ name: 'Test soap' }] })` then `ok('shopping_list', {})` contains it, `ok('refresh_shopping_list', {})` deep-equals `{ queued: true }`.
- [ ] **Step 2:** Run `node --test test/api.test.cjs` — expected FAIL (missing tools).
- [ ] **Step 3:** Register the tools with zod shapes.
- [ ] **Step 4:** Run `npm test` — expected pass.
- [ ] **Step 5:** Commit `feat(mcp): inventory and shopping list tools`.

### Task 5: Web views

**Files:**
- Modify: `web/index.cjs` (routes next to `/prices`, lines 429-436), `web/public/index.html` (`MORE_VIEWS` 1596, loader map 1613, a `<section class="view">` per view after `#v-prices` ~1238, loaders after `loadPrices` ~2634)

**Interfaces:**
- Routes: `GET /inventory?q&include_untracked` → array; `POST /inventory/used-up {item_key, unit?}`; `POST /inventory/tracking {item_key, unit, tracked}`; `GET /shopping` → `shoppingList`; `POST /shopping {add|bought|dismiss|remove}`; `POST /shopping/refresh` → `{queued:true}`. Writes pass `actor`.
- Views: `MORE_VIEWS` gets `['inventory', <existing icon id>, 'Inventory'], ['shopping', <existing icon id>, 'Shopping List']` right after `prices`; loaders `loadInventory`, `loadShopping` in the `load` map.

- [ ] **Step 1:** Add the routes; extend `test/web-db.test.cjs` only if it already exercises routes, else rely on Task 4 tests for the db layer.
- [ ] **Step 2:** Build both views in the Prices style (`.sec-head`, `.rowcard`, `.empty`, `esc()` on every name/reason): Inventory sections Running low / In stock / Used up / Learning / collapsed Not tracked, each row with a usage bar and a Used up button; Shopping List with add field, tick/dismiss/remove, price hint, estimated total, "Update now" and the AI status line.
- [ ] **Step 3:** Run `LEDGER_SHOPPING_TIMER=off FINANCE_DB=<tmp> node web/index.cjs` with seeded receipts, open it in the browser pane, check both views render and actions work; `npm test` passes.
- [ ] **Step 4:** Commit `feat(web): Inventory and Shopping List views`.

### Task 6: iPhone models and API wrappers

**Files:**
- Create: `ios/Sources/Ledger/Models/InventoryItem.swift`, `ios/Sources/Ledger/Models/ShoppingList.swift`
- Modify: `ios/Sources/Ledger/API/LedgerAPI+Tools.swift` (after `priceHistory` ~line 194), `scripts/ios-build.sh` (logic-check file list), `ios/Checks/main.swift`

**Interfaces:**
- Produces: `struct InventoryItem: Decodable, Identifiable, Hashable, Sendable` (fields from Task 1 Item, camelCase; `id = "\(itemKey)|\(unit)"`; `enum Status: String` with the seven statuses and an `unknown` fallback); `struct ShoppingList: Decodable, Sendable { items: [ShoppingItem]; totalCents: Int?; ai: AIStatus }`, `struct ShoppingItem: Decodable, Identifiable, Hashable, Sendable`.
- `LedgerAPI.inventory(includeUntracked: Bool) → [InventoryItem]`, `markUsedUp(_ item: InventoryItem)`, `setTracking(_ item: InventoryItem, tracked: Bool?)`, `shoppingList() → ShoppingList`, `updateShopping(add: [String] = [], bought: [Int] = [], dismiss: [Int] = [], remove: [Int] = [])`, `refreshShopping()`.

- [ ] **Step 1:** Add checks to `ios/Checks/main.swift` decoding a raw JSON sample of each (with `.convertFromSnakeCase`) and asserting `status == .runningLow`, `daysLeft == 2`, `ShoppingList.items.count`, `ai.pending == false`, and an unknown status decodes to `.unknown`.
- [ ] **Step 2:** Run `wsl -e bash -lc 'taskset -c 0-3 bash /mnt/d/Home-lab/ledger/.claude/worktrees/<wt>/scripts/ios-build.sh'` — expected LOGIC CHECK DID NOT COMPILE.
- [ ] **Step 3:** Add the models (Foundation-only) to the logic-check list and the wrappers.
- [ ] **Step 4:** Re-run the build — expected `LOGIC OK`, `BUILD OK (0 errors)`.
- [ ] **Step 5:** Commit `feat(ios): inventory and shopping models`.

### Task 7: iPhone screens

**Files:**
- Create: `ios/Sources/Ledger/Inventory/InventoryView.swift`, `InventoryRow.swift`, `InventoryItemView.swift`; `ios/Sources/Ledger/Shopping/ShoppingListView.swift`, `ShoppingRow.swift`
- Modify: `Shared/Route.swift` (`case inventory`, `case inventoryItem(InventoryItem)`, `case shoppingList`), `Shared/RouteDestination.swift`, `More/MoreView.swift` (two `link(...)` rows directly under Item Prices, existing `KitIcon` members)

- [ ] **Step 1:** Build the screens in the PricesView pattern (`KitScreen(..., showsBack: true)`, `LoadableView`, `.refreshable`, cards like `PriceRow`): Inventory sections as in the spec with a Used up button per row; item detail with purchase list from `item_price_history`, Track/Don't track; Shopping List with add field, tick/swipe actions, price hint, total, Update now and the AI status footer.
- [ ] **Step 2:** Run the iOS build — expected `BUILD OK (0 errors, 0 warnings)`, `LOGIC OK`.
- [ ] **Step 3:** Commit `feat(ios): Inventory and Shopping List screens`.

### Task 8: Docs and pull request

**Files:**
- Modify: `docs/api.md` (six tools), `docs/extras.md` (Shopping List AI: key file, `LEDGER_ANTHROPIC_KEY_FILE`, what is sent, rules-only without a key), `README.md` feature list.

- [ ] **Step 1:** Write the docs with made-up examples only.
- [ ] **Step 2:** `npm test` and the iOS build pass; scrub-scan the branch diff.
- [ ] **Step 3:** Commit, push the branch, open one PR on `saiteja007-mv/ledger` (owner approves the merge). After merge: message the agent that runs the owner's server to port Tasks 1-4 and set the key env; port Tasks 6-7 to the owner's private iOS app repo; install on the phone only when the owner says "install".
