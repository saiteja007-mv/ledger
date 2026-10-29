// ledger-api end to end: starts web/api.cjs on a throwaway DB and a random port, then drives it
// over HTTP the way the iOS app does. Never touches .data/finance.sqlite. Lives at
// test/api.test.cjs, so `npm test` runs it.
const { test, before, after } = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawn } = require('node:child_process')

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ledger-api-test-'))
let base, child, iconServer
const iconHits = []

before(async () => {
  // A stand-in icon service: a PNG for uber.com, 404 for everything else. No test touches the real one.
  iconServer = require('node:http').createServer((req, res) => {
    const domain = new URL(req.url, 'http://x').searchParams.get('d')
    iconHits.push(domain)
    if (domain !== 'uber.com') { res.writeHead(404); return res.end() }
    res.writeHead(200, { 'Content-Type': 'image/png' })
    res.end(Buffer.concat([Buffer.from('iVBORw0KGgo=', 'base64'), Buffer.alloc(200, 1)]))
  })
  await new Promise((resolve) => iconServer.listen(0, '127.0.0.1', resolve))
  child = spawn(process.execPath, [path.join(__dirname, '..', 'web', 'api.cjs')], {
    // CLAUDE_BIN=false: an uploaded photo's bill read fails fast instead of starting a real session.
    env: {
      ...process.env, FINANCE_DB: path.join(dir, 'finance.sqlite'), LEDGER_API_PORT: '0', CLAUDE_BIN: '/bin/false',
      LEDGER_LOGO_DIR: path.join(dir, 'logos'),
      LEDGER_LOGO_URL: `http://127.0.0.1:${iconServer.address().port}/icon?d={domain}`,
    },
    stdio: ['ignore', 'pipe', 'inherit'],
  })
  base = await new Promise((resolve, reject) => {
    child.stdout.on('data', (d) => { const m = String(d).match(/listening on (http:\/\/\S+)/); if (m) resolve(m[1]) })
    child.on('exit', (code) => reject(new Error(`api.cjs exited ${code}`)))
  })
})
after(async () => {
  iconServer.close()
  const exited = new Promise((resolve) => child.once('exit', resolve))
  child.kill()
  await exited
  // Windows holds the SQLite file a moment after the process exits; a temp dir left behind there is harmless.
  try { fs.rmSync(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }) } catch {}
})

const call = async (name, args = {}, headers = {}) => {
  const r = await fetch(`${base}/api/tool/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(args) })
  return { status: r.status, body: await r.json() }
}
const ok = async (name, args) => {
  const r = await call(name, args)
  assert.equal(r.status, 200, `${name}: ${JSON.stringify(r.body)}`)
  assert.equal(r.body.ok, true)
  return r.body.result
}

const p2 = (x) => String(x).padStart(2, '0')
const now = new Date()
const day = `${now.getFullYear()}-${p2(now.getMonth() + 1)}-${p2(now.getDate())}`
// 1x1 PNG
const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='

test('every MCP tool is exposed, plus the app extras', async () => {
  const tools = await (await fetch(`${base}/api/tools`)).json()
  const names = new Set(tools.map((t) => t.name))
  for (const n of ['get_status', 'list_accounts', 'list_transactions', 'search_transactions', 'spending_summary',
    'category_breakdown', 'budget_status', 'list_balances', 'reconcile_account', 'review_queue', 'suggest_categories',
    'list_audit', 'list_receipts', 'get_receipt', 'get_receipt_image', 'upsert_transactions', 'record_balance',
    'add_receipt', 'item_prices', 'item_price_history', 'set_receipt_items', 'set_category', 'mark_reviewed',
    'void_transaction', 'set_budget', 'categories', 'networth', 'upload_receipt_photo', 'merchant_logo',
    'inventory', 'mark_used_up', 'set_item_tracking', 'shopping_list', 'update_shopping_list', 'refresh_shopping_list']) assert.ok(names.has(n), n)
})

test('inventory and shopping list tools work over the API', async () => {
  const ago = (n) => { const d = new Date(now.getTime() - n * 864e5); return `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}` }
  for (const n of [10, 3]) await ok('add_receipt', { merchant: 'Corner Market', purchased_at: `${ago(n)}T10:00:00`, total: 3.49,
    line_items: [{ name: 'Test dish soap 1 gal', price: 3.49 }] })

  const inv = await ok('inventory', {})
  const soap = inv.find((i) => i.name.toLowerCase().includes('test dish soap'))
  assert.ok(soap, JSON.stringify(inv))
  assert.equal(soap.last_price, 3.49)
  assert.equal(soap.last_price_cents, 349)

  const used = await ok('mark_used_up', { item_key: soap.item_key })
  assert.equal(used.at, day)
  assert.equal(used.item_key, soap.item_key)
  assert.equal((await ok('set_item_tracking', { item_key: soap.item_key, unit: soap.unit, tracked: false })).tracked, 0)
  assert.equal((await ok('set_item_tracking', { item_key: soap.item_key, unit: soap.unit, tracked: null })).tracked, null)

  await ok('update_shopping_list', { add: [{ name: 'Test soap', qty: 2 }] })
  const list = await ok('shopping_list', {})
  assert.ok(list.items.some((i) => i.name === 'Test soap' && i.qty === 2), JSON.stringify(list))
  assert.equal(typeof list.total, 'number')
  assert.equal(typeof list.total_cents, 'number')

  assert.deepEqual(await ok('refresh_shopping_list', {}), { queued: true })
})

test('merchant descriptors resolve to a brand domain, and people and noise to nothing', () => {
  const { resolveDomain } = require('../server/logos.cjs')
  const cases = {
    'UBER *TRIP HELP.UBER.COMCA': 'uber.com',
    'WM SUPERCENTER #4321 555-010-0100 IL': 'walmart.com',
    'WAL-MART #4321 SPRINGFIELDIL': 'walmart.com',
    'COSTCO WHSE #0123 SPRINGFIELDIL': 'costco.com',
    'Amazon web services aws.amazon.coWA': 'aws.amazon.com',
    'AMAZON MKTPLACE PMTS Amzn.com/billWA': 'amazon.com',
    'APPLE.COM/BILL 866-712-7753 CA': 'apple.com',
    'AMC 1234 ONLINE 555-010-0200 IL': 'amctheatres.com',
    'BESTBUY.COM, 888-BESTBUY': 'bestbuy.com',
    'QT 123 SPRINGFIELD IL': 'quiktrip.com',
    'COSTCO BY INSTACART INSTACART.COMCA': 'costco.com',
    'SomeShop https://www.exampleshop.com/checkout': 'exampleshop.com',
  }
  for (const [descriptor, domain] of Object.entries(cases)) assert.equal(resolveDomain(descriptor), domain, descriptor)
  for (const none of ['Alex', 'Sam', 'Income', 'Own account', 'Fund transfer from savings, 2026-06-',
    'SQ *CORNER CAFE Springfield IL', '', null]) assert.equal(resolveDomain(none), null, String(none))
})

test('merchant_logo returns a cached PNG for a brand and nothing for the rest', async () => {
  const hit = await ok('merchant_logo', { merchant: 'UBER *TRIP HELP.UBER.COMCA' })
  assert.equal(hit.domain, 'uber.com')
  assert.equal(hit.mime_type, 'image/png')
  assert.ok(Buffer.from(hit.image_base64, 'base64').subarray(0, 4).toString('latin1').includes('PNG'))
  await ok('merchant_logo', { merchant: 'Uber trip home.uber.com' })
  assert.equal(iconHits.filter((d) => d === 'uber.com').length, 1, 'the second ask is served from the cache')

  assert.deepEqual(await ok('merchant_logo', { merchant: 'Alex' }), { domain: null })
  assert.deepEqual(await ok('merchant_logo', { merchant: 'Cloudflare' }), { domain: null })   // alias, but the stand-in has no icon
  await ok('merchant_logo', { merchant: 'Cloudflare invoice' })
  assert.equal(iconHits.filter((d) => d === 'cloudflare.com').length, 1, 'a miss is remembered too')
  assert.equal((await call('merchant_logo', {})).body.result.domain, null)
})

test('browser-shaped and malformed requests are refused', async () => {
  assert.equal((await call('get_status', {}, { Origin: 'https://evil.example' })).status, 403)
  assert.equal((await call('get_status', {}, { 'Content-Type': 'text/plain' })).status, 403)
  assert.equal((await fetch(`${base}/api/tool/get_status`)).status, 405)
  assert.equal((await call('drop_everything')).status, 404)
  const bad = await call('list_transactions', { limit: 'lots' })
  assert.equal(bad.status, 400)
  assert.equal(bad.body.ok, false)
})

test('log, categorize, review, void, reconcile, budget', async () => {
  const up = await ok('upsert_transactions', { source: 'ledger-ios', items: [
    { account: 'Cash', posted_at: `${day}T09:15:00`, direction: 'expense', amount: 12.5, merchant: 'Uber trip' },
    { account: 'Cash', posted_at: `${day}T09:20:00`, direction: 'expense', amount: 3, merchant: 'Coffee cart', category: 'Food' },
  ] })
  assert.equal(up.inserted, 2)
  const [uber, coffee] = up.ids

  assert.equal((await ok('review_queue', {})).length, 2)
  const sugg = await ok('suggest_categories', {})
  assert.equal(sugg.find((s) => s.id === uber).category, 'Transport')
  assert.equal((await ok('set_category', { id: uber, category: 'Transport' })).category, 'Transport')
  assert.deepEqual(await ok('mark_reviewed', { ids: [uber, coffee] }), { updated: 2 })
  assert.equal((await ok('review_queue', {})).length, 0)

  assert.equal((await ok('search_transactions', { q: 'uber' })).length, 1)
  assert.deepEqual(await ok('void_transaction', { id: coffee, reason: 'test' }), { voided: 1 })
  assert.equal((await ok('list_transactions', { account: 'Cash' })).length, 1)

  await ok('record_balance', { account: 'Cash', as_of_date: '2020-01-01', balance: 100 })
  await ok('record_balance', { account: 'Cash', as_of_date: day, balance: 87.5 })
  const rec = await ok('reconcile_account', { account: 'Cash', from: '2020-01-01', to: day })
  assert.equal(rec.drift_cents, 0)

  await ok('set_budget', { category: 'Transport', limit: 10 })
  assert.equal((await ok('budget_status', {}))[0].status, 'over')
  assert.equal((await ok('spending_summary', {})).expense_cents, 1250)
  assert.equal((await ok('category_breakdown', {}))[0].total_cents, 1250)

  const nw = await ok('networth', {})
  assert.equal(nw.net_cents, 8750)
  assert.ok((await ok('categories', {})).includes('Groceries'))
})

test('receipt photo upload, image round trip, bill read queued', async () => {
  assert.equal((await call('upload_receipt_photo', { image_base64: PNG, ext: 'jpg' })).status, 400)   // bytes are not a JPEG
  const up = await ok('upload_receipt_photo', { image_base64: PNG, ext: 'png', merchant: 'Corner store' })
  assert.equal(up.bill_status, 'pending')
  const got = await ok('get_receipt', { id: up.id })
  assert.equal(got.has_image, true)
  const img = await ok('get_receipt_image', { id: up.id })
  assert.equal(img.mime_type, 'image/png')
  assert.ok(img.image_base64.length > 20)
  // CLAUDE_BIN is /bin/false, so the queued read must settle as failed, not hang in pending.
  let status
  for (let i = 0; i < 50 && !['failed', 'done'].includes(status); i++) {
    await new Promise((r) => setTimeout(r, 100))
    status = (await ok('get_receipt', { id: up.id })).bill_status
  }
  assert.equal(status, 'failed')
})
