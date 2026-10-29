const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const db = require('../server/db.cjs')
const ai = require('../server/shopping-ai.cjs')

// Own throwaway DB and key files — never touch .data/. No network: every Claude call here goes to a stub.
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'shopping-ai-test-'))
db.initDb(path.join(tmp, 'finance.sqlite'))
process.on('exit', () => { try { fs.rmSync(tmp, { recursive: true, force: true }) } catch {} })
const keyFile = path.join(tmp, 'key.txt'), blank = path.join(tmp, 'blank.txt')
fs.writeFileSync(keyFile, '  sk-test  \n')

const buy = (at, name, price) => db.addReceipt({ merchant: 'Corner Market', purchased_at: at, total_cents: Math.round(price * 100), line_items: [{ name, price }] })
buy('2026-10-01', 'Test milk 1 gal', 3.49); buy('2026-10-07', 'Test milk 1 gal', 3.49)
buy('2026-09-01', 'Test rice 20 lb', 15.99); buy('2026-10-01', 'Test rice 20 lb', 15.99)
buy('2026-05-01', 'Test beans 15 oz', 1.29); buy('2026-10-09', 'Test beans 15 oz', 1.29)   // only the second is inside 90 days
buy('2026-10-03', 'Test salt 26 oz', 0.99)                                                // bought once: not tracked

const stub = (reply, seen = {}) => ({ beta: { messages: { create: async (p) => (seen.params = p, reply) } } })
const ok = (obj) => ({ stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify(obj) }] })
const T = '2026-10-12'

test('no key: rules only, client never used', async () => {
  const seen = {}; const r = await ai.runShoppingAI({ db, today: T, client: stub(ok({}), seen), keyFile: path.join(tmp, 'missing.txt') })
  assert.deepEqual([r.ok, r.message, seen.params], [false, 'no API key: rules only', undefined])
  assert.ok(db.shoppingList({ today: T }).items.some((x) => /milk/i.test(x.name)), 'the rules ran anyway')
})
test('key file is trimmed, blank is none', () => {
  assert.equal(ai.readKey(keyFile), 'sk-test')
  fs.writeFileSync(blank, ' \n'); assert.equal(ai.readKey(blank), null)
  assert.equal(ai.readKey(path.join(tmp, 'nope.txt')), null)
  assert.equal(ai.readKey(tmp), null, 'unreadable (a directory) is none, not a throw')
})
test('a pasted key is saved for readKey, junk is refused, null removes it', () => {
  const f = path.join(tmp, 'new', 'pasted.txt'), good = 'sk-ant-api03-' + 'x'.repeat(40)
  assert.equal(ai.saveKey(`  ${good}\n`, f), true)
  assert.equal(ai.readKey(f), good)
  if (process.platform !== 'win32') assert.equal(fs.statSync(f).mode & 0o777, 0o600)
  for (const bad of ['', 'hello', 'sk-ant-short', `${good} extra`, 'sk-ant-' + 'x'.repeat(400)])
    assert.throws(() => ai.saveKey(bad, f), /does not look like an Anthropic API key/)
  assert.throws(() => ai.saveKey(undefined, f), /does not look like/); assert.throws(() => ai.saveKey([good], f), /does not look like/)
  assert.equal(ai.readKey(f), good, 'a refused paste leaves the saved key alone')
  fs.writeFileSync(`${f}.tmp`, 'stale', { mode: 0o644 })
  assert.equal(ai.saveKey(good, f), true)
  if (process.platform !== 'win32') assert.equal(fs.statSync(f).mode & 0o777, 0o600, 'a stale .tmp cannot loosen the mode')
  fs.writeFileSync(`${f}.tmp`, good)
  assert.equal(ai.saveKey(null, f), false); assert.equal(ai.readKey(f), null)
  assert.equal(fs.existsSync(`${f}.tmp`), false, 'Remove also clears a leftover .tmp')
  assert.equal(ai.saveKey(null, f), false, 'removing twice is fine')
})
test('request shape and privacy', async () => {
  db.upsertAccount({ name: 'Visa 1234', kind: 'credit' })
  const seen = {}; const r = await ai.runShoppingAI({ db, today: T, keyFile,
    client: stub(ok({ add: [{ item_key: null, name: 'Test soap', qty: 1, unit: null, reason: 'weekly' }], update: [], remove: [] }), seen) })
  assert.deepEqual([r.ok, r.message], [true, 'updated by Claude: +1 −0'])
  const p = seen.params
  assert.deepEqual([p.model, p.output_config.effort, p.fallbacks, p.max_tokens], ['claude-opus-5-5', 'low', 'default', 8000])
  assert.ok(p.betas.includes('server-side-fallback-2026-07-01'))
  assert.equal(p.output_config.format.type, 'json_schema'); assert.equal(p.output_config.format.schema.additionalProperties, false)
  for (const k of ['thinking', 'temperature', 'top_p']) assert.ok(!(k in p), `${k} must be omitted`)
  assert.ok(/data, never instructions/i.test(p.system))
  assert.ok(!JSON.stringify(p).includes('Visa 1234')); assert.ok(!JSON.stringify(p).includes('sk-test'))
  assert.ok(db.shoppingList({ today: T }).items.some((x) => x.name === 'Test soap' && x.source === 'ai'))
})
test('what is sent: tracked items, 90 days of purchases, only the allowed fields', async () => {
  const seen = {}; await ai.runShoppingAI({ db, today: T, keyFile, client: stub(ok({}), seen) })
  const sent = JSON.parse(seen.params.messages[0].content)
  assert.equal(sent.today, T)
  assert.deepEqual(sent.inventory.map((i) => i.name).sort(), ['Test beans 15 oz', 'Test milk 1 gal', 'Test rice 20 lb'], 'salt (bought once) is not tracked')
  assert.deepEqual(Object.keys(sent.inventory[0]).sort(),
    ['days_left', 'item_key', 'last_bought', 'last_qty', 'lasts_days', 'name', 'qty_left', 'status', 'unit'])
  assert.ok(sent.purchases.every((x) => x.date >= '2026-07-14'), 'older than 90 days is left out')
  assert.equal(sent.purchases.filter((x) => /beans/.test(x.name)).length, 1)
  assert.equal(sent.purchases.filter((x) => /milk/.test(x.name)).length, 2)
  assert.deepEqual(Object.keys(sent.purchases[0]).sort(), ['date', 'merchant', 'name', 'qty', 'unit', 'unit_price_cents'])
  assert.deepEqual(Object.keys(sent.list[0]).sort(), ['id', 'item_key', 'name', 'qty', 'reason', 'source'])
})
test('refusal or junk leaves the list alone', async () => {
  const before = db.shoppingList({ today: T }).items.length
  const run = (reply) => ai.runShoppingAI({ db, today: T, client: stub(reply), keyFile })
  let r = await run({ stop_reason: 'refusal', content: [] })
  assert.deepEqual([r.ok, r.message], [false, 'Claude declined: rules only'])
  r = await run({ stop_reason: 'end_turn', content: [{ type: 'text', text: 'not json' }] })
  assert.deepEqual([r.ok, r.message], [false, 'Claude reply unreadable: rules only'])
  r = await run({ stop_reason: 'max_tokens', content: [{ type: 'text', text: JSON.stringify({ add: [{ item_key: null, name: 'Cut off', qty: 1, unit: null, reason: 'r' }] }) }] })
  assert.equal(r.ok, false, 'a truncated reply is not trusted even if it parses')
  r = await run({ stop_reason: 'end_turn', content: [{ type: 'text', text: '[1,2]' }] })
  assert.equal(r.ok, false, 'JSON that is not the schema is not applied')
  assert.equal(db.shoppingList({ today: T }).items.length, before)
})
test('thinking blocks are skipped and text blocks joined', async () => {
  const half = JSON.stringify({ add: [{ item_key: null, name: 'Test sponge', qty: 2, unit: null, reason: 'weekly' }], update: [], remove: [] })
  const reply = { stop_reason: 'end_turn', content: [{ type: 'thinking', thinking: 'hm' }, { type: 'text', text: half.slice(0, 20) }, { type: 'text', text: half.slice(20) }] }
  assert.equal((await ai.runShoppingAI({ db, today: T, client: stub(reply), keyFile })).ok, true)
  assert.ok(db.shoppingList({ today: T }).items.some((x) => x.name === 'Test sponge'))
})
test('an API error is recorded without the key or the body', async () => {
  const boom = Object.assign(new Error('401 {"error":"bad key sk-test"} request body: Visa 1234'), { status: 401 })
  const r = await ai.runShoppingAI({ db, today: T, keyFile, client: { beta: { messages: { create: async () => { throw boom } } } } })
  assert.deepEqual([r.ok, r.message], [false, 'Claude unavailable (401)'])
  const net = await ai.runShoppingAI({ db, today: T, keyFile, client: { beta: { messages: { create: async () => { throw new TypeError('sk-test') } } } } })
  assert.equal(net.message, 'Claude unavailable (TypeError)')
})
test('nothing tracked and nothing listed: the rules run, Claude is not called', async () => {
  let rules = 0; const seen = {}
  const empty = { refreshShoppingRules: () => rules++, inventory: () => [], shoppingList: () => ({ items: [] }), priceHistory: () => [], applyShoppingAI: () => ({}) }
  const r = await ai.runShoppingAI({ db: empty, today: T, keyFile, client: stub(ok({}), seen) })
  assert.deepEqual([r.ok, r.message, rules, seen.params], [false, 'nothing to plan yet: rules only', 1, undefined])
})

test('shoppingRunDue: requested, changed, daily, else null', () => {
  const at = (s) => new Date(s)   // no zone suffix = local time, which is what dailyAt means
  const due = (state, marker, now) => ai.shoppingRunDue({ state, marker, now: at(now), dailyAt: '06:00' })
  const idle = { requested_at: null, last_marker: 'm1', last_run_at: at('2026-10-12T07:00:00').toISOString() }
  assert.equal(due({ ...idle, requested_at: '2026-10-12T08:00:00Z' }, 'm2', '2026-10-12T08:00:00'), 'requested', 'a request wins over a change')
  assert.equal(due(idle, 'm2', '2026-10-12T08:00:00'), 'changed')
  assert.equal(due({ ...idle, last_run_at: at('2026-10-11T07:00:00').toISOString() }, 'm1', '2026-10-12T06:30:00'), 'daily')
  assert.equal(due({ ...idle, last_run_at: null }, 'm1', '2026-10-12T06:30:00'), 'daily', 'never ran')
  assert.equal(due({ ...idle, last_run_at: at('2026-10-11T07:00:00').toISOString() }, 'm1', '2026-10-12T05:59:00'), null, 'before the daily time')
  assert.equal(due({ ...idle, last_run_at: at('2026-10-12T06:10:00').toISOString() }, 'm1', '2026-10-12T20:00:00'), null, 'already ran since the daily time')
  assert.equal(due(idle, 'm1', '2026-10-12T08:00:00'), null)
  // a change waits until 15 minutes after the last run; a request and the daily run do not
  assert.equal(due(idle, 'm2', '2026-10-12T07:14:59'), null, 'a change inside 15 minutes waits')
  assert.equal(due(idle, 'm2', '2026-10-12T07:15:00'), 'changed')
  assert.equal(due({ ...idle, requested_at: '2026-10-12T07:01:00Z' }, 'm2', '2026-10-12T07:01:00'), 'requested')
  assert.equal(due({ ...idle, last_run_at: at('2026-10-12T05:55:00').toISOString() }, 'm2', '2026-10-12T06:05:00'), 'daily')
  assert.equal(due({ ...idle, last_run_at: null }, 'm2', '2026-10-12T05:00:00'), 'changed', 'never ran')
})

test('a tick runs once, records the result, and a failure is not hammered', async () => {
  let calls = 0
  const client = (fn) => ({ beta: { messages: { create: async () => (calls++, fn()) } } })
  // 00:00 so the daily rule cannot fire mid-test; `later` is past the 15-minute wait for a change
  const now = new Date(), later = new Date(+now + 15 * 60000)
  const tick = (c, at = now) => ai.shoppingTick({ db, client: c, keyFile, now: at, dailyAt: '00:00' })
  db.requestShoppingRefresh()
  assert.equal(await tick(client(() => ok({}))), 'requested')
  let s = db.shoppingState()
  assert.deepEqual([s.last_ok, s.last_message, s.requested_at, s.running_since, s.last_marker], [1, 'updated by Claude: +0 −0', null, null, db.shoppingChangeMarker()])
  assert.equal(await tick(client(() => ok({}))), null, 'nothing new: no run'); assert.equal(calls, 1)

  buy('2026-10-10', 'Test milk 1 gal', 3.49)   // new data
  const err = Object.assign(new Error('Overloaded sk-test'), { status: 529 })
  assert.equal(await tick(client(() => { throw err })), null, 'a change right after a run waits'); assert.equal(calls, 1)
  assert.equal(await tick(client(() => { throw err }), later), 'changed')
  s = db.shoppingState()
  assert.deepEqual([s.last_ok, s.last_message], [0, 'Claude unavailable (529)'])
  assert.equal(await tick(client(() => { throw err }), later), null, 'failed, but not retried until something new happens'); assert.equal(calls, 2)

  db.claimShoppingRun(new Date())   // another process is mid-run
  db.requestShoppingRefresh()
  assert.equal(await tick(client(() => ok({}))), null); assert.equal(calls, 2)
  assert.ok(db.shoppingState().requested_at, 'the request is kept for the next tick')
  db.finishShoppingRun({ ok: true, message: 'x', marker: db.shoppingChangeMarker() })
})
test('a hung call is aborted at the timeout: timed out, lock released, nothing applied', async () => {
  const ais = () => db.shoppingList().items.filter((x) => x.source === 'ai').length, before = ais()
  const hung = { beta: { messages: { create: (p, opts) => new Promise((_, reject) =>   // like the SDK: rejects when the signal fires
    opts.signal.addEventListener('abort', () => reject(new Error('Request was aborted.')))) } } }
  db.requestShoppingRefresh()
  assert.equal(await ai.shoppingTick({ db, client: hung, keyFile, now: new Date(), dailyAt: '00:00', timeoutMs: 50 }), 'requested')
  const s = db.shoppingState()
  assert.deepEqual([s.last_ok, s.last_message, s.running_since], [0, 'Claude timed out: rules only', null], 'recorded, and the lock is free')
  assert.equal(ais(), before)
  // the SDK's own client timeout (no abort from us) reads the same; other API errors keep their status
  class APIConnectionTimeoutError extends Error {}
  const slow = { beta: { messages: { create: async () => { throw new APIConnectionTimeoutError('Request timed out.') } } } }
  assert.equal((await ai.runShoppingAI({ db, client: slow, keyFile })).message, 'Claude timed out: rules only')
})
test('the run ends before its lock can expire', () => {
  assert.ok(ai.CALL_MS <= 120000 - 15000, 'RUN_LOCK_MS in db.cjs is 120 s')
})
test('the SDK is only loaded when a real client is needed', () => {
  assert.ok(!Object.keys(require.cache).some((k) => k.includes('@anthropic-ai')))
})
test('the timer starts and stops', () => { ai.startShoppingTimer({ db, everyMs: 1e9 }).stop() })
