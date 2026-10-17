// ledger-api — the JSON API behind the Ledger iOS app (web/api.cjs).
//
// Tailnet only: listens on 127.0.0.1:8098 (LEDGER_API_PORT) and is published with
//   sudo -n tailscale serve --bg --https=8448 http://127.0.0.1:8098
// Tailnet membership is the auth , so the app holds no secret.
//
// Interface: every MCP tool in server/mcp.mjs is POST /api/tool/<name> with the tool's JSON
// arguments as the body, answered with {ok:true, result} or {ok:false, error}. The tools run
// in-process through the MCP SDK's in-memory transport, so zod validation, money formatting and
// the ledger rules are the MCP server's own; nothing here re-implements them. Three app-only
// extras share the namespace (EXTRAS below). GET /api/tools lists everything with its schema.
//
// Security, as Pulse does it: a POST with an Origin header, or one that is not
// Content-Type: application/json, is refused. Browsers always send Origin on cross-site POSTs and
// cannot send JSON without a preflight, so no web page on a tailnet device can drive this
// (CSRF, DNS rebinding). No shell, no eval: the only child process is bill.cjs's fixed argv.
const http = require('node:http')
const fs = require('node:fs')
const path = require('node:path')
const crypto = require('node:crypto')

const db = require('../server/db.cjs')
const categorize = require('../server/categorize.cjs')
const reconcile = require('../server/reconcile.cjs')
const bill = require('../server/bill.cjs')
const networth = require('../server/networth.cjs')
const logos = require('../server/logos.cjs')

const PORT = Number(process.env.LEDGER_API_PORT || 8098)
const HOST = process.env.LEDGER_API_HOST || '127.0.0.1'
const ACTOR = 'ledger-ios'
const MAX_JSON = 1_000_000
const MAX_PHOTO = 12 * 1024 * 1024                    // same cap as the web uploader
const MAX_PHOTO_JSON = Math.ceil(MAX_PHOTO * 4 / 3) + 64_000   // base64 + the other fields

db.initDb()

// ---- receipt photos ---------------------------------------------------------

// Photos are read into a bill one at a time, as in web/index.cjs: each read is a `claude -p` session.
let billQueue = Promise.resolve()
function queueBill(id) {
  db.setBillStatus(id, 'pending')
  billQueue = billQueue.then(async () => {
    const r = db.getReceipt(id)
    const file = r && db.receiptImageFile(r.image_path)
    if (!file) return db.setBillStatus(id, 'failed', 'the photo is not on disk')
    db.setBillStatus(id, 'reading')
    try {
      db.applyBill(id, await bill.extract(file))
    } catch (e) {
      db.setBillStatus(id, 'failed', String(e.message).slice(0, 300))
      console.error(`[ledger-api] bill #${id} failed: ${e.message}`)
    }
  })
}

// Magic bytes, checked before ImageMagick ever sees the file: the extension alone is the client's word.
const MAGIC = {
  jpg: (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
  png: (b) => b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
  heic: (b) => b.subarray(4, 8).toString('latin1') === 'ftyp',
  webp: (b) => b.subarray(0, 4).toString('latin1') === 'RIFF' && b.subarray(8, 12).toString('latin1') === 'WEBP',
  pdf: (b) => b.subarray(0, 5).toString('latin1') === '%PDF-',
}

class BadInput extends Error { constructor(m, status = 400) { super(m); this.status = status } }
const optString = (v, name, max = 200) => {
  if (v == null || v === '') return null
  if (typeof v !== 'string' || v.length > max) throw new BadInput(`${name} must be a string of at most ${max} characters`)
  return v.trim()
}

function uploadReceiptPhoto(a) {
  const ext = String(a.ext || 'jpg').toLowerCase().replace(/^jpeg$/, 'jpg')
  if (!MAGIC[ext]) throw new BadInput(`ext must be one of ${Object.keys(MAGIC).join(', ')}`)
  if (typeof a.image_base64 !== 'string' || !a.image_base64) throw new BadInput('image_base64 required')
  const buf = Buffer.from(a.image_base64, 'base64')
  if (!buf.length) throw new BadInput('image_base64 is empty or not base64')
  if (buf.length > MAX_PHOTO) throw new BadInput(`photo is ${(buf.length / 1048576).toFixed(1)} MB; the limit is 12 MB`, 413)
  if (!MAGIC[ext](buf)) throw new BadInput(`that file is not a .${ext}`)

  const merchant = optString(a.merchant, 'merchant')
  const purchased_at = optString(a.purchased_at, 'purchased_at', 19)
  if (purchased_at && !/^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?)?$/.test(purchased_at)) throw new BadInput('purchased_at must be YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS')
  if (a.total != null && !(typeof a.total === 'number' && Number.isFinite(a.total) && a.total >= 0)) throw new BadInput('total must be a positive number')
  const total_cents = a.total == null ? null : db.toCents(a.total)
  let txId = null
  if (a.transaction_id != null) {
    if (!Number.isInteger(a.transaction_id) || !db.getTransaction(a.transaction_id)) throw new BadInput(`no transaction ${a.transaction_id}`)
    txId = a.transaction_id
  }

  // Content-addressed, as the web uploader does: the same photo twice is one file.
  const name = `${crypto.createHash('sha256').update(buf).digest('hex')}.${ext}`
  fs.mkdirSync(db.receiptDir(), { recursive: true })
  fs.writeFileSync(path.join(db.receiptDir(), name), buf, { mode: 0o600 })
  db.audit('upload_receipt_image', ACTOR, { name }, 1, `${buf.length} bytes`)

  let matched = null
  if (!txId && total_cents != null && purchased_at) {
    matched = db.matchReceiptToTransaction({ total_cents, purchased_at })
    txId = matched?.id ?? null
  }
  // No total typed: Claude fills it in, so key the receipt on the photo (as web/index.cjs does).
  const external_id = total_cents == null ? `img:${name}` : undefined
  const r = db.addReceipt({ merchant, purchased_at, total_cents, transaction_id: txId, image_path: name, external_id, source: 'ios' })
  queueBill(r.id)
  return { id: r.id, inserted: r.inserted, image_path: name, bytes: buf.length, transaction_id: txId, bill_status: 'pending' }
}

// ---- tools ------------------------------------------------------------------

const EXTRAS = {
  categories: {
    description: 'Category names for pickers: every category in use plus the standard set. Categories have no table; a new one is real once assigned.',
    input_schema: { type: 'object', properties: {} },
    run: () => [...new Set([...db.distinctCategories(), ...categorize.DEFAULT_RULES.map((r) => r.category)])].sort(),
  },
  networth: {
    description: 'Each account\'s balance as of now (latest reported balance plus ledger movement since), grouped Banking/Cards/Cash/People, plus net worth in USD. Same numbers as the web app.',
    input_schema: { type: 'object', properties: {} },
    run: () => networth.netWorth(),
  },
  merchant_logo: {
    description: 'The brand icon for a merchant descriptor as the bank wrote it ("UBER *TRIP HELP.UBER.COMCA"): {domain, image_base64, mime_type: "image/png"}, or {domain: null} when it is a person, a transfer or an unrecognised brand. Icons are fetched once from a public icon service by the server and cached on disk; only the brand domain leaves the server.',
    input_schema: {
      type: 'object', required: ['merchant'],
      properties: { merchant: { type: 'string', description: 'The transaction\'s merchant text.' } },
    },
    run: (a) => logos.logoFor(optString(a.merchant, 'merchant', 300) ?? ''),
  },
  upload_receipt_photo: {
    description: 'Store a receipt photo from the phone, create its receipt row, auto-attach it to a matching transaction when total + purchased_at are given, and queue it to be read into a bill (line items, tax, total). Poll get_receipt for bill_status.',
    input_schema: {
      type: 'object', required: ['image_base64'],
      properties: {
        image_base64: { type: 'string', description: 'The photo bytes, base64. 12 MB max.' },
        ext: { type: 'string', enum: Object.keys(MAGIC), default: 'jpg' },
        merchant: { type: 'string' }, purchased_at: { type: 'string' }, total: { type: 'number' },
        transaction_id: { type: 'integer' },
      },
    },
    run: uploadReceiptPhoto,
  },
}

let client = null
let mcpTools = []

async function connectTools() {
  const { buildServer } = await import('../server/mcp.mjs')
  const { InMemoryTransport } = await import('@modelcontextprotocol/sdk/inMemory.js')
  const { Client } = await import('@modelcontextprotocol/sdk/client/index.js')
  const [serverSide, clientSide] = InMemoryTransport.createLinkedPair()
  await buildServer({ db, categorize, reconcile }).connect(serverSide)
  client = new Client({ name: 'ledger-api', version: '1.0.0' })
  await client.connect(clientSide)
  mcpTools = (await client.listTools()).tools
}

// MCP results are text blocks of JSON (or "Error: ..." with isError); get_receipt_image adds an
// image block, which becomes image_base64 + mime_type on the result.
async function runTool(name, args) {
  let res
  try {
    res = await client.callTool({ name, arguments: args })
  } catch (e) {
    throw new BadInput(String(e.message || e).replace(/^MCP error -?\d+: /, ''))   // e.g. invalid params
  }
  const texts = res.content.filter((c) => c.type === 'text').map((c) => c.text)
  if (res.isError) throw new BadInput(texts.join(' ').replace(/^Error: /, '').replace(/^MCP error -?\d+: /, ''))
  const result = JSON.parse(texts[0] ?? 'null')
  const image = res.content.find((c) => c.type === 'image')
  return image ? { ...result, image_base64: image.data, mime_type: image.mimeType } : result
}

const toolList = () => [
  ...mcpTools.map((t) => ({ name: t.name, description: t.description, input_schema: t.inputSchema })),
  ...Object.entries(EXTRAS).map(([name, e]) => ({ name, description: e.description, input_schema: e.input_schema, extra: true })),
]

// ---- http -------------------------------------------------------------------

const send = (res, code, body) => {
  const s = JSON.stringify(body)
  res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Content-Length': Buffer.byteLength(s) })
  res.end(s)
}

const readBody = (req, cap) => new Promise((resolve, reject) => {
  const declared = Number(req.headers['content-length'])
  if (Number.isFinite(declared) && declared > cap) return reject(new BadInput('payload too large', 413))
  const chunks = []; let n = 0
  req.on('data', (c) => { n += c.length; if (n > cap) { reject(new BadInput('payload too large', 413)); req.destroy() } else chunks.push(c) })
  req.on('end', () => resolve(Buffer.concat(chunks)))
  req.on('error', reject)
})

const isAppRequest = (req) => !req.headers.origin &&
  String(req.headers['content-type'] || '').split(';')[0].trim().toLowerCase() === 'application/json'

const server = http.createServer(async (req, res) => {
  const p = new URL(req.url, 'http://localhost').pathname
  try {
    if (req.method === 'GET' && p === '/healthz') return send(res, 200, { ok: true, app: 'ledger-api', ...db.stats() })
    if (req.method === 'GET' && p === '/api/tools') return send(res, 200, toolList())

    const m = p.match(/^\/api\/tool\/([a-z_]{1,64})$/)
    if (!m) return send(res, 404, { ok: false, error: 'not found' })
    if (req.method !== 'POST') return send(res, 405, { ok: false, error: 'POST only' })
    if (!isAppRequest(req)) return send(res, 403, { ok: false, error: 'app requests only' })

    const name = m[1]
    const extra = Object.hasOwn(EXTRAS, name) ? EXTRAS[name] : null
    if (!extra && !mcpTools.some((t) => t.name === name)) return send(res, 404, { ok: false, error: `no tool ${name}` })

    const raw = await readBody(req, name === 'upload_receipt_photo' ? MAX_PHOTO_JSON : MAX_JSON)
    let args
    try { args = JSON.parse(raw.toString('utf8') || '{}') } catch { throw new BadInput('body is not JSON') }
    if (!args || typeof args !== 'object' || Array.isArray(args)) throw new BadInput('body must be a JSON object')

    const result = extra ? await extra.run(args) : await runTool(name, args)
    return send(res, 200, { ok: true, result })
  } catch (e) {
    if (!(e instanceof BadInput)) console.error('[ledger-api]', e)
    if (!res.headersSent) send(res, e.status || 500, { ok: false, error: String(e.message || e).slice(0, 500) })
  }
})

connectTools().then(() => {
  server.listen(PORT, HOST, () => {
    console.log(`[ledger-api] listening on http://${HOST}:${server.address().port} (${mcpTools.length} MCP tools + ${Object.keys(EXTRAS).length} extras)`)
    // Resume reads a restart interrupted. Only this API's own uploads: finance-web resumes its own.
    for (const id of db.receiptsAwaitingBill()) if (db.getReceipt(id)?.source === 'ios') queueBill(id)
  })
}).catch((e) => { console.error('[ledger-api] fatal:', e); process.exit(1) })
