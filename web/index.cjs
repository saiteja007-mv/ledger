// finance-web — the browser UI for finance-mcp.
//
// Deliberately a SEPARATE process on a separate port and hostname from the MCP server.
// index.cjs (the MCP one) still serves ONLY /mcp; this serves only the UI + its REST API.
// They share `.data/finance.sqlite` through the same db.cjs — one storage layer, two front
// doors, no duplicated money logic.
//
// Auth is a shared token exchanged for an HMAC-signed cookie. Cloudflare Access in front is
// the intended outer boundary, but this holds bank data: it does not rely on a header it
// cannot verify, the way a dashboard of cron jobs reasonably can.
const http = require('node:http')
const fs = require('node:fs')
const path = require('node:path')
const crypto = require('node:crypto')
const { ingestAlert } = require('../server/alerts.cjs')

const db = require('../server/db.cjs')
const categorize = require('../server/categorize.cjs')
const reconcile = require('../server/reconcile.cjs')
const bill = require('../server/bill.cjs')
const fx = require('../server/fx.cjs')
const { startShoppingTimer, readKey, saveKey } = require('../server/shopping-ai.cjs')

const PORT = Number(process.env.FINANCE_WEB_PORT || 42832)
const HOST = process.env.FINANCE_WEB_HOST || '127.0.0.1'
const PUBLIC = path.join(__dirname, 'public')
const DATA_DIR = path.join(__dirname, '..', '.data')

// Open the DB first: db.receiptDir() reports the directory for the database actually in use,
// so it has to run after initDb rather than falling back to the default path.
db.initDb()                    // sets WAL + busy_timeout; see db.cjs
// Image location is defined once, in db.cjs, so the MCP server resolves the same files.
const RECEIPT_DIR = db.receiptDir()
const SESSION_DAYS = 30

// Every uploaded photo is read into a bill (server/bill.cjs), one at a time: each read is a
// `claude -p` session, and a burst of uploads shouldn't become a burst of model sessions.
let billQueue = Promise.resolve()
function queueBill(id) {
  db.setBillStatus(id, 'pending')
  billQueue = billQueue.then(async () => {
    const r = db.getReceipt(id)
    const file = r && db.receiptImageFile(r.image_path)
    if (!file) return db.setBillStatus(id, 'failed', 'the photo is not on disk')
    db.setBillStatus(id, 'reading')
    try {
      const after = db.applyBill(id, await bill.extract(file))
      console.log(`[finance-web] bill #${id}: ${after.line_items?.length ?? 0} items, ${after.bill_data.line_items.length} read`)
    } catch (e) {
      db.setBillStatus(id, 'failed', String(e.message).slice(0, 300))
      console.error(`[finance-web] bill #${id} failed: ${e.message}`)
    }
  })
}
const MAX_UPLOAD = 12 * 1024 * 1024

// ---- dates ---------------------------------------------------------------
const p2 = (x) => String(x).padStart(2, '0')
const today = () => { const n = new Date(); return `${n.getFullYear()}-${p2(n.getMonth() + 1)}-${p2(n.getDate())}` }
const monthStart = (d = today()) => d.slice(0, 8) + '01'
const nextMonth = (d = today()) => { const x = new Date(d.slice(0, 8) + '01T00:00:00Z'); x.setUTCMonth(x.getUTCMonth() + 1); return x.toISOString().slice(0, 10) }

// ---- auth ----------------------------------------------------------------

// Separate from the MCP bearer token on purpose: this one gets pasted into a phone browser
// and lives in a cookie, so it should be revocable without breaking the ChatGPT connector.
function loadWebToken() {
  if (process.env.FINANCE_WEB_TOKEN) return process.env.FINANCE_WEB_TOKEN
  const file = path.join(DATA_DIR, 'web-token.txt')
  try { const v = fs.readFileSync(file, 'utf8').trim(); if (v) return v } catch {}
  fs.mkdirSync(DATA_DIR, { recursive: true })
  const tok = crypto.randomBytes(24).toString('base64url')
  fs.writeFileSync(file, tok + '\n', { mode: 0o600 })
  console.log(`[finance-web] generated web token -> ${file}`)
  return tok
}

const TOKEN = loadWebToken()

// Separate write-only token for the iPhone Shortcut that forwards bank alerts. It can only
// reach POST /api/ingest/bofa, so leaking it lets someone add review-queue rows, nothing more.
function loadIngestToken() {
  if (process.env.FINANCE_INGEST_TOKEN) return process.env.FINANCE_INGEST_TOKEN
  const file = path.join(DATA_DIR, 'ingest-token.txt')
  try { const v = fs.readFileSync(file, 'utf8').trim(); if (v) return v } catch {}
  fs.mkdirSync(DATA_DIR, { recursive: true })
  const tok = crypto.randomBytes(24).toString('base64url')
  fs.writeFileSync(file, tok + '\n', { mode: 0o600 })
  return tok
}
const INGEST_TOKEN = loadIngestToken()
// Signing key is derived from the token, so rotating the token invalidates every session.
const SIGNING_KEY = crypto.createHmac('sha256', TOKEN).update('finance-web/session').digest()

const sign = (payload) => crypto.createHmac('sha256', SIGNING_KEY).update(payload).digest('base64url')

function mintCookie() {
  const exp = Math.floor(Date.now() / 1000) + SESSION_DAYS * 86400
  const payload = String(exp)
  return `${payload}.${sign(payload)}`
}

function cookieValid(raw) {
  if (!raw) return false
  const i = raw.lastIndexOf('.')
  if (i < 1) return false
  const payload = raw.slice(0, i), mac = raw.slice(i + 1)
  const want = sign(payload)
  if (mac.length !== want.length || !crypto.timingSafeEqual(Buffer.from(mac), Buffer.from(want))) return false
  return Number(payload) > Math.floor(Date.now() / 1000)
}

const parseCookies = (h) => Object.fromEntries((h || '').split(';').map((c) => {
  const i = c.indexOf('='); return i < 0 ? [c.trim(), ''] : [c.slice(0, i).trim(), decodeURIComponent(c.slice(i + 1).trim())]
}).filter(([k]) => k))

// Behind Authentik (2026-10-08): the outpost adds X-Authentik-Proof — a secret only Authentik and
// this app know (scope mapping "Proxy proof: money") — to every request it forwards after the
// Google login, next to X-authentik-email. The email header alone is forgeable; the proof is not.
const AUTHENTIK_OWNER = process.env.AUTHENTIK_OWNER_EMAIL || ''
const AUTHENTIK_PROOF = (() => { try { return fs.readFileSync(path.join(DATA_DIR, 'authentik-proof.txt'), 'utf8').trim() } catch { return '' } })()
const sha = (s) => crypto.createHash('sha256').update(String(s ?? '')).digest()
const viaAuthentik = (req) => Boolean(AUTHENTIK_PROOF) && req.headers['x-authentik-email'] === AUTHENTIK_OWNER &&
  crypto.timingSafeEqual(sha(req.headers['x-authentik-proof']), sha(AUTHENTIK_PROOF))
const authed = (req) => viaAuthentik(req) || cookieValid(parseCookies(req.headers.cookie).fw)

// Constant-time compare that does not leak length. A wrong-length guess must cost the same
// as a right-length one, so both sides are hashed to a fixed width first.
function tokenEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a ?? '')).digest()
  const hb = crypto.createHash('sha256').update(String(b ?? '')).digest()
  return crypto.timingSafeEqual(ha, hb)
}

// A 24-byte random token is not brute-forceable, but throttling costs three lines and
// protects the case where someone later swaps in a human-memorable passphrase.
let failures = 0
const throttle = () => new Promise((r) => setTimeout(r, failures > 4 ? Math.min(4000, (failures - 4) * 500) : 0))

// The actor recorded in the audit log. Access, when configured, names a real human.
const actorFrom = (req) => req.headers['cf-access-authenticated-user-email'] || 'web'

// ---- http helpers --------------------------------------------------------

const json = (res, code, body) => {
  const s = JSON.stringify(body)
  res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Content-Length': Buffer.byteLength(s) })
  res.end(s)
}

const readBody = (req, cap = 1_000_000) => new Promise((resolve, reject) => {
  const chunks = []; let n = 0
  req.on('data', (c) => { n += c.length; if (n > cap) { req.destroy(); reject(new Error('payload too large')) } else chunks.push(c) })
  req.on('end', () => resolve(Buffer.concat(chunks)))
  req.on('error', reject)
})

const readJson = async (req) => { const b = await readBody(req); try { return JSON.parse(b.toString('utf8') || '{}') } catch { return {} } }
const readBodyText = async (req) => {
  const b = (await readBody(req)).toString('utf8')
  try { const j = JSON.parse(b); return typeof j === 'string' ? j : (j.text ?? j.body ?? j.message ?? '') } catch { return b }
}

const ingestBofa = (text) => ingestAlert({ db, text, today: today(), actor: 'iphone-shortcut' })

const money = (c) => (c == null ? null : Math.round(c) / 100)
// Absent query params arrive as null, and Number(null) is 0 — so a missing ?limit used to
// mean LIMIT 0 and an empty list. Absent/blank now means "use the default".
const num = (v, d = null) => { if (v == null || v === '') return d; const n = Number(v); return Number.isFinite(n) ? n : d }
const centsFrom = (o, key = 'amount') => o[`${key}_cents`] != null ? Math.round(Number(o[`${key}_cents`])) : db.toCents(o[key])

const MIME = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.heic': 'image/heic', '.pdf': 'application/pdf' }

// ---- account classification -----------------------------------------------
//
// accounts.kind may be empty on older rows; these name lists fill it in so classification
// never requires an UPDATE to the accounts table. Your own account names live in
// .data/account-kinds.json (gitignored), e.g. {"credit":["Visa 1234"],"checking":["Checking"]}.
// ponytail: name-keyed, not data-driven — add the name there when a new account needs it.
const ACCOUNT_KINDS = (() => {
  const d = { credit: [], checking: ['Checking'], cash: ['Cash'], people: ['Splitwise', 'Friends'] }
  try { return { ...d, ...JSON.parse(fs.readFileSync(path.join(DATA_DIR, 'account-kinds.json'), 'utf8')) } } catch { return d }
})()
const CARD_NAMES = new Set(ACCOUNT_KINDS.credit)
const BANKING_NAMES = new Set(ACCOUNT_KINDS.checking)
const CASH_NAMES = new Set(ACCOUNT_KINDS.cash)
const PEOPLE_NAMES = new Set(ACCOUNT_KINDS.people)

function inferKind(name) {
  if (CARD_NAMES.has(name)) return 'credit'
  if (BANKING_NAMES.has(name)) return 'checking'
  if (CASH_NAMES.has(name)) return 'cash'
  if (PEOPLE_NAMES.has(name)) return 'people'
  return null
}

const GROUP_LABELS = { banking: 'Banking', cards: 'Cards', cash: 'Cash', people: 'People' }
const GROUP_ORDER = ['banking', 'cards', 'cash', 'people']
function groupKeyFor(kind) {
  if (kind === 'checking') return 'banking'
  if (kind === 'credit') return 'cards'
  if (kind === 'cash' || kind === 'wallet' || kind === 'virtual') return 'cash'
  return 'people'
}

// One account row extended with net-worth fields. `signed_cents` is the account's
// contribution to net worth (a liability's owed balance flips sign); `drift_cents` is
// ledger movement recorded strictly AFTER the anchor date — never a from-zero implied
// balance compared against a reported one (that comparison is the D1 bug this replaces).
// usd_rate converts this account's native currency for net worth; balances stay native.
function extendAccount(a, usd_rate = 1) {
  const tx = db.listTransactions({ account: a.name, limit: 100000 })
  const snaps = db.listBalances(a.name)
  const kind_resolved = a.kind || inferKind(a.name) || 'other'
  const is_liability = kind_resolved === 'credit'
  const implied_cents = reconcile.impliedBalance(tx)
  const latest = snaps[0] || null
  const anchor = latest ? { as_of_date: latest.as_of_date, cents: latest.balance_cents } : null
  const verified = snaps.length > 0
  const raw_drift_cents = anchor
    ? tx.filter((t) => t.posted_at.slice(0, 10) > anchor.as_of_date).reduce((s, t) => s + reconcile.delta(t), 0)
    : null
  // drift_cents means "change in this account's contribution to net worth since the anchor",
  // so it needs the same liability sign-flip as signed_cents (was previously unflipped — D1 bug).
  const drift_cents = raw_drift_cents == null ? null : (is_liability ? -raw_drift_cents : raw_drift_cents)
  // The balance as of NOW, in the account's own reporting convention (owed, for a card). The
  // anchor alone is only what a statement said on its date; an account row should show today's
  // number. Reading the anchor as "the balance" made a checking account look stuck at its
  // statement figure after money had moved through it. drift_cents already carries the liability
  // sign-flip, so this addition is correct for assets and liabilities alike.
  const current_cents = anchor ? anchor.cents + (drift_cents ?? 0) : implied_cents
  // Net-worth contribution as of NOW, from current_cents rather than the anchor. Deriving it
  // from the anchor made the group totals and net worth disagree with the rows above them:
  // an account row showed today's balance while its group total still showed the old anchor.
  const signed_cents = Math.round((is_liability ? -current_cents : current_cents) * usd_rate)
  return {
    ...a, transactions: tx.length, implied_cents, latest_balance: anchor ? { as_of_date: anchor.as_of_date, cents: anchor.cents } : null,
    kind_resolved, is_liability, verified, anchor, signed_cents, signed_is_estimate: !anchor,
    drift_cents, current_cents, group: groupKeyFor(kind_resolved),
  }
}

// Net worth is in USD, so each non-USD account is converted at today's live rate. If the rate
// can't be fetched the account counts at 1:1 rather than breaking the page; usd_rate: null flags it.
async function extendAccounts() {
  const out = []
  for (const a of db.listAccounts()) {
    let rate = 1, ok = true
    try { rate = await fx.usdRate(a.currency) } catch (e) { ok = false; console.error(`[fx] ${e.message}`) }
    out.push({ ...extendAccount(a, rate), usd_rate: ok ? rate : null })
  }
  return out
}

// ---- API -----------------------------------------------------------------

async function api(req, res, url) {
  const p = url.pathname.replace(/^\/api/, '')
  const q = url.searchParams
  const GET = req.method === 'GET'
  const POST = req.method === 'POST'
  const actor = actorFrom(req)

  // -- period helpers shared by the dashboard widgets
  const from = q.has('from') ? q.get('from') : monthStart()
  const to = q.has('to') ? q.get('to') : nextMonth()

  if (GET && p === '/bootstrap') {
    const accounts = await extendAccounts()
    return json(res, 200, {
      ok: true, stats: db.stats(), accounts, categories: db.distinctCategories(),
      budgets: db.listBudgets(), today: today(), month: monthStart().slice(0, 7),
      unreviewed: db.countTransactions({ reviewed: 0 }),
      unattached_receipts: db.listReceipts({ limit: 500, unattached_only: true }).length,
    })
  }

  if (GET && p === '/summary') {
    const s = db.summary({ from, to })
    return json(res, 200, { ...s, income: money(s.income_cents), expense: money(s.expense_cents), net: money(s.net_cents) })
  }

  if (GET && p === '/breakdown') {
    return json(res, 200, db.categoryBreakdown({ from, to, direction: q.get('direction') || 'expense', limit: num(q.get('limit'), 20) })
      .map((r) => ({ category: r.category, count: r.n, cents: r.cents, total: money(r.cents) })))
  }

  if (GET && p === '/monthly') return json(res, 200, db.monthlySeries({ months: num(q.get('months'), 12) }))

  // The category list is a union, not a stored table: categories the ledger actually uses,
  // plus the standard set from categorize.cjs so a fresh category is one tap rather than a
  // typo waiting to happen. A category becomes "real" the moment it is assigned to a row.
  if (GET && p === '/categories') {
    const stats = db.categoryStats({ from: q.get('from') || undefined, to: q.get('to') || undefined })
    const seen = new Map(stats.map((r) => [r.category, {
      category: r.category, count: r.n, expense_cents: r.expense_cents, income_cents: r.income_cents,
      last_used: r.last_used, standard: false, in_use: true,
    }]))
    for (const rule of categorize.DEFAULT_RULES) {
      const hit = seen.get(rule.category)
      if (hit) hit.standard = true
      else seen.set(rule.category, { category: rule.category, count: 0, expense_cents: 0, income_cents: 0,
        last_used: null, standard: true, in_use: false })
    }
    const budgets = new Map(db.listBudgets().map((b) => [b.category, b.limit_cents]))
    const rows = [...seen.values()].map((c) => ({ ...c, budget_cents: budgets.get(c.category) ?? null }))
    rows.sort((a, b) => b.expense_cents - a.expense_cents || b.count - a.count || a.category.localeCompare(b.category))
    return json(res, 200, rows)
  }

  if (POST && p === '/categories/rename') {
    const b = await readJson(req)
    if (!b.from) return json(res, 400, { ok: false, error: 'from required' })
    if (!b.to) return json(res, 400, { ok: false, error: 'to required — use void, not a blank rename, to remove data' })
    return json(res, 200, { ok: true, ...db.renameCategory(b.from, b.to) })
  }

  if (GET && p === '/transactions') {
    const f = { from: q.get('from') || undefined, to: q.get('to') || undefined,
      account: q.get('account') || undefined, category: q.get('category') || undefined,
      direction: q.get('direction') || undefined, q: q.get('q') || undefined,
      reviewed: q.get('reviewed') === '0' ? 0 : q.get('reviewed') === '1' ? 1 : undefined,
      include_voided: q.get('include_voided') === '1' }
    const limit = Math.min(num(q.get('limit'), 50), 500)
    const offset = num(q.get('offset'), 0)
    return json(res, 200, {
      total: db.countTransactions(f),
      limit, offset,
      rows: db.listTransactions({ ...f, limit, offset }).map((t) => ({ ...t, amount: money(t.amount_cents), reviewed: !!t.reviewed, voided: !!t.voided_at })),
    })
  }

  if (POST && p === '/transactions') {
    const b = await readJson(req)
    const cents = centsFrom(b)
    if (cents == null) return json(res, 400, { ok: false, error: 'amount required' })
    if (cents < 0) return json(res, 400, { ok: false, error: 'amount must be positive — direction carries the sign' })
    const r = db.upsertTransactions(await fx.fillRates([{ ...b, amount_cents: cents, amount: undefined, reviewed: 1 }], db), { source: b.source || 'web', actor })
    // id comes back so the caller can attach a receipt photo to the row it just created.
    return json(res, 200, { ok: !r.errors.length, ...r, id: r.ids[0] ?? null })
  }

  let m
  if ((m = p.match(/^\/transactions\/(\d+)$/))) {
    const id = Number(m[1])
    if (POST) return json(res, 200, { ok: true, tx: db.updateTransaction(id, await readJson(req)) })
    const t = db.getTransaction(id)
    if (!t) return json(res, 404, { ok: false, error: 'not found' })
    return json(res, 200, { ok: true, tx: { ...t, amount: money(t.amount_cents), reviewed: !!t.reviewed, voided: !!t.voided_at },
      receipts: db.receiptsForTransaction(id) })
  }
  if (POST && (m = p.match(/^\/transactions\/(\d+)\/void$/))) {
    const { reason } = await readJson(req)
    return json(res, 200, { ok: true, ...db.voidTransaction(Number(m[1]), reason || `via web by ${actor}`) })
  }
  if (POST && p === '/transactions/review') {
    const { ids } = await readJson(req)
    if (!Array.isArray(ids) || !ids.length) return json(res, 400, { ok: false, error: 'ids[] required' })
    return json(res, 200, { ok: true, ...db.markReviewed(ids.map(Number)) })
  }

  if (GET && p === '/review-queue') {
    const rows = reconcile.reviewQueue(db.listTransactions({ reviewed: 0, limit: 500 }))
    const suggestions = Object.fromEntries(categorize.suggestBatch(rows).map((s) => [s.id, s]))
    return json(res, 200, rows.map((r) => ({ ...r, amount: money(r.amount_cents), suggestion: suggestions[r.id] || null })))
  }

  if (GET && p === '/suggestions') {
    const rows = db.listTransactions({ limit: 500 }).filter((r) => !r.category || r.category === 'Other')
    return json(res, 200, categorize.suggestBatch(rows))
  }

  // -- receipts
  if (GET && p === '/receipts') {
    return json(res, 200, db.listReceipts({ limit: num(q.get('limit'), 200), unattached_only: q.get('unattached') === '1' })
      .map((r) => ({ ...r, total: money(r.total_cents), tax: money(r.tax_cents) })))
  }
  if (GET && (m = p.match(/^\/receipts\/(\d+)$/))) {
    const r = db.getReceipt(Number(m[1]))
    return r ? json(res, 200, r) : json(res, 404, { ok: false, error: 'not found' })
  }
  if (POST && p === '/receipts') {
    const b = await readJson(req)
    const total_cents = centsFrom(b, 'total')
    let txId = b.transaction_id ? Number(b.transaction_id) : null
    let matched = null
    if (!txId && total_cents != null && b.purchased_at) {
      matched = db.matchReceiptToTransaction({ total_cents, purchased_at: b.purchased_at })
      txId = matched?.id ?? null
    }
    // Photo with no total typed: Claude fills it in, so the natural key (merchant|date|total)
    // would be blank and every such upload would collide — key it on the photo instead.
    const external_id = b.external_id || (total_cents == null && b.image_path ? `img:${b.image_path}` : undefined)
    const r = db.addReceipt({ ...b, external_id, total_cents, tax_cents: centsFrom(b, 'tax'), transaction_id: txId, source: 'web' })
    if (b.image_path && r.id) queueBill(r.id)
    return json(res, 200, { ok: true, ...r, bill_status: b.image_path ? 'pending' : null,
      matched: matched ? { ...matched, amount: money(matched.amount_cents) } : null })
  }
  if (POST && (m = p.match(/^\/receipts\/(\d+)\/attach$/))) {
    const { transaction_id } = await readJson(req)
    // Validate before the insert so a bad id is a 400 with a sentence, not a 500 with
    // "FOREIGN KEY constraint failed" leaking the schema at whoever typed it.
    const txId = transaction_id == null ? null : Number(transaction_id)
    if (txId != null && !db.getTransaction(txId)) return json(res, 400, { ok: false, error: `no transaction ${txId}` })
    if (!db.getReceipt(Number(m[1]))) return json(res, 404, { ok: false, error: 'receipt not found' })
    return json(res, 200, { ok: true, receipt: db.attachReceipt(Number(m[1]), txId) })
  }
  if (POST && (m = p.match(/^\/receipts\/(\d+)\/bill$/))) {
    const r = db.getReceipt(Number(m[1]))
    if (!r) return json(res, 404, { ok: false, error: 'receipt not found' })
    if (!db.receiptImageFile(r.image_path)) return json(res, 400, { ok: false, error: 'this receipt has no photo to read' })
    queueBill(r.id)
    return json(res, 200, { ok: true, bill_status: 'pending' })
  }
  if (GET && p === '/receipts/match') {
    const t = num(q.get('total_cents')); const at = q.get('purchased_at')
    if (t == null || !at) return json(res, 400, { ok: false, error: 'total_cents and purchased_at required' })
    const hit = db.matchReceiptToTransaction({ total_cents: t, purchased_at: at })
    return json(res, 200, hit ? { ...hit, amount: money(hit.amount_cents) } : null)
  }
  if (POST && (m = p.match(/^\/receipts\/(\d+)\/items$/))) {
    const b = await readJson(req)
    if (!Array.isArray(b.line_items)) return json(res, 400, { ok: false, error: 'line_items must be an array' })
    const n = db.setReceiptItems(Number(m[1]), b.line_items, { tax_cents: centsFrom(b, 'tax') })
    if (n == null) return json(res, 404, { ok: false, error: 'receipt not found' })
    return json(res, 200, { ok: true, items: n })
  }

  // Prices: what each grocery item has cost over time, derived from receipt line items.
  if (GET && p === '/prices') {
    return json(res, 200, db.priceItems({ q: q.get('q') || null, merchant: q.get('merchant') || null, limit: num(q.get('limit'), 200) }))
  }
  if (GET && (m = p.match(/^\/prices\/(.+)$/))) {
    const item_key = decodeURIComponent(m[1])
    return json(res, 200, { item_key, history: db.priceHistory(item_key, { unit: q.get('unit') || null }) })
  }

  // Inventory and Shopping List. "Update now" only sets the refresh marker: the timer started below is
  // the one place that calls Claude, so no route here ever waits on it.
  if (GET && p === '/inventory') {
    const untracked = q.get('include_untracked')
    return json(res, 200, db.inventory({ q: q.get('q') || null, include_untracked: untracked === '1' || untracked === 'true', today: today() }))
  }
  if (POST && p === '/inventory/used-up') {
    const b = await readJson(req)
    if (typeof b.item_key !== 'string' || !b.item_key) return json(res, 400, { ok: false, error: 'item_key required' })
    try {
      return json(res, 200, { ok: true, ...db.markUsedUp({ item_key: b.item_key, unit: b.unit || null, at: today(), actor }) })
    } catch (e) {
      if (/^no purchases of /.test(e.message)) return json(res, 400, { ok: false, error: e.message })
      throw e
    }
  }
  if (POST && p === '/inventory/tracking') {
    const b = await readJson(req)
    if (typeof b.item_key !== 'string' || !b.item_key || typeof b.unit !== 'string' || !b.unit) return json(res, 400, { ok: false, error: 'item_key and unit required' })
    if (b.tracked !== null && typeof b.tracked !== 'boolean') return json(res, 400, { ok: false, error: 'tracked must be true, false or null' })
    return json(res, 200, { ok: true, ...db.setItemTracking({ item_key: b.item_key, unit: b.unit, tracked: b.tracked, actor }) })
  }
  if (GET && p === '/shopping') return json(res, 200, db.shoppingList({ today: today() }))
  if (POST && p === '/shopping/refresh') return json(res, 200, { ok: true, ...db.requestShoppingRefresh() })
  // The Claude key for the Shopping List. Write-only: the page only ever learns whether one is set.
  if (GET && p === '/shopping/key') return json(res, 200, { set: readKey() != null })
  if (POST && p === '/shopping/key') {
    const { key } = (await readJson(req)) || {}
    if (key !== null && typeof key !== 'string') return json(res, 400, { ok: false, error: 'key must be a string, or null to remove it' })
    let set
    try { set = saveKey(key) } catch (e) {
      return json(res, 400, { ok: false, error: /look like/.test(e.message) ? e.message : 'could not save the key file' })
    }
    db.audit('set_anthropic_key', actor, { set }, 1)
    if (set) db.requestShoppingRefresh()   // Claude takes over on the next tick
    return json(res, 200, { ok: true, set })
  }
  if (POST && p === '/shopping') {
    const { add, bought, dismiss, remove } = await readJson(req)
    return json(res, 200, { ok: true, ...db.updateShoppingList({ add, bought, dismiss, remove, actor, today: today() }) })
  }

  // Raw-bytes upload. No multipart parser: the browser can POST a File directly as the
  // body, which makes this a Buffer write instead of a dependency and a state machine.
  if (POST && p === '/upload') {
    const ext = String(q.get('ext') || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '')
    if (!['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'].includes(ext)) return json(res, 400, { ok: false, error: `unsupported type .${ext}` })
    // Reject on the declared length BEFORE reading. Tripping the streaming cap below
    // destroys the socket, which reaches the browser as a network error rather than a
    // message — every real upload sends Content-Length, so this is the path that answers.
    const declared = Number(req.headers['content-length'])
    if (Number.isFinite(declared) && declared > MAX_UPLOAD) {
      json(res, 413, { ok: false, error: `file is ${(declared / 1048576).toFixed(1)} MB — the limit is 12 MB` })
      return req.destroy()
    }
    let buf
    try { buf = await readBody(req, MAX_UPLOAD) } catch { return }  // cap tripped; socket already gone
    if (!buf.length) return json(res, 400, { ok: false, error: 'empty upload' })
    // Content-addressed: re-uploading the same photo overwrites itself instead of
    // accumulating duplicates, and an abandoned form leaves at most one orphan file.
    const name = `${crypto.createHash('sha256').update(buf).digest('hex')}.${ext}`
    fs.mkdirSync(RECEIPT_DIR, { recursive: true })
    fs.writeFileSync(path.join(RECEIPT_DIR, name), buf, { mode: 0o600 })
    db.audit('upload_receipt_image', actor, { name }, 1, `${buf.length} bytes`)
    return json(res, 200, { ok: true, file: name, bytes: buf.length })
  }

  // -- balances / budgets / accounts
  if (GET && p === '/balances') {
    return json(res, 200, db.listBalances(q.get('account') || undefined).map((b) => ({ ...b, balance: money(b.balance_cents) })))
  }
  if (POST && p === '/balances') {
    const b = await readJson(req)
    const c = centsFrom(b, 'balance')
    if (c == null) return json(res, 400, { ok: false, error: 'balance required' })
    return json(res, 200, { ok: true, ...db.recordBalance({ account: b.account, as_of_date: b.as_of_date, balance_cents: c }) })
  }
  if (GET && p === '/budgets') {
    return json(res, 200, reconcile.budgetStatus({
      budgets: db.listBudgets(),
      spendByCategory: db.categoryBreakdown({ from: monthStart(), to: nextMonth(), direction: 'expense', limit: 200 }).map((r) => ({ category: r.category, cents: r.cents })),
      period_label: monthStart().slice(0, 7),
    }))
  }
  if (POST && p === '/budgets') {
    const b = await readJson(req)
    const c = centsFrom(b, 'limit')
    if (c == null) return json(res, 400, { ok: false, error: 'limit required' })
    return json(res, 200, { ok: true, ...db.setBudget({ category: b.category, period: b.period || 'monthly', limit_cents: c }) })
  }
  if (POST && p === '/accounts') {
    const b = await readJson(req)
    if (!b.name) return json(res, 400, { ok: false, error: 'name required' })
    return json(res, 200, { ok: true, account: db.upsertAccount(b) })
  }

  if (GET && p === '/reconcile') {
    const account = q.get('account')
    if (!account) return json(res, 400, { ok: false, error: 'account required' })
    const snaps = db.listBalances(account).slice().sort((a, b) => a.as_of_date.localeCompare(b.as_of_date))
    if (snaps.length < 2) return json(res, 200, { ok: false, error: `need 2+ balance snapshots for ${account}; have ${snaps.length}` })
    const open = snaps[0], close = snaps[snaps.length - 1]
    const tx = db.listTransactions({ account, from: open.as_of_date, to: close.as_of_date + 'T23:59:59', limit: 100000 })
    const r = reconcile.reconcileAccount({ account, from: open.as_of_date, to: close.as_of_date,
      opening_cents: open.balance_cents, closing_cents: close.balance_cents, transactions: tx })
    return json(res, 200, { ok: true, ...r, opening: money(r.opening_cents), closing: money(r.closing_cents),
      ledger_movement: money(r.ledger_movement_cents), drift: money(r.drift_cents) })
  }

  if (GET && p === '/networth') {
    const accounts = await extendAccounts()
    const groups = GROUP_ORDER.map((key) => {
      const rows = accounts.filter((a) => a.group === key)
      return { key, label: GROUP_LABELS[key], total_cents: rows.reduce((s, a) => s + a.signed_cents, 0), accounts: rows }
    })
    const assets_cents = accounts.filter((a) => !a.is_liability).reduce((s, a) => s + a.signed_cents, 0)
    const liabilities_cents = accounts.filter((a) => a.is_liability).reduce((s, a) => s - a.signed_cents, 0)
    return json(res, 200, {
      assets_cents, liabilities_cents, net_cents: assets_cents - liabilities_cents,
      unverified_count: accounts.filter((a) => !a.verified).length, groups,
    })
  }

  if (GET && p === '/audit') return json(res, 200, db.listAudit(num(q.get('limit'), 100)))

  return json(res, 404, { ok: false, error: `no route for ${req.method} ${p}` })
}

// ---- server --------------------------------------------------------------

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`)
  const p = url.pathname

  try {
    if (p === '/healthz') return json(res, 200, { ok: true, app: 'finance-web', ...db.stats() })

    if (p === '/api/login' && req.method === 'POST') {
      await throttle()
      const { token } = await readJson(req)
      if (!tokenEqual(token, TOKEN)) { failures++; return json(res, 401, { ok: false, error: 'wrong token' }) }
      failures = 0
      const secure = req.headers['x-forwarded-proto'] === 'https' ? ' Secure;' : ''
      res.writeHead(200, {
        'Content-Type': 'application/json',
        'Set-Cookie': `fw=${mintCookie()}; HttpOnly;${secure} SameSite=Lax; Path=/; Max-Age=${SESSION_DAYS * 86400}`,
      })
      return res.end(JSON.stringify({ ok: true }))
    }
    if (p === '/api/logout' && req.method === 'POST') {
      res.writeHead(200, { 'Content-Type': 'application/json', 'Set-Cookie': 'fw=; HttpOnly; Path=/; Max-Age=0' })
      return res.end(JSON.stringify({ ok: true }))
    }
    if (p === '/api/session') return json(res, 200, { ok: authed(req) })

    if (p === '/api/ingest/bofa' && req.method === 'POST') {
      const bearer = (req.headers.authorization || '').replace(/^Bearer\s+/i, '')
      if (!tokenEqual(bearer, INGEST_TOKEN)) {
        console.log(`[ingest] 401 bad token (auth header ${req.headers.authorization ? 'present' : 'missing'})`)
        await throttle(); failures++; return json(res, 401, { ok: false, error: 'bad ingest token' })
      }
      const text = await readBodyText(req)
      const r = ingestBofa(text)
      console.log(`[ingest] ${r.ok ? (r.duplicate ? 'duplicate' : 'logged') : r.kind}: ${r.message || r.error} | text=${JSON.stringify(String(text).slice(0, 200))}`)
      return json(res, 200, r)
    }

    if (!authed(req)) {
      if (p.startsWith('/api/')) return json(res, 401, { ok: false, error: 'not signed in' })
      // Unauthenticated page loads still get the app shell; it renders the sign-in card.
    }

    if (p.startsWith('/api/')) return await api(req, res, url)

    // Receipt images. Name is validated as content-hash + known extension, so no user
    // string ever reaches the filesystem — traversal is impossible by construction.
    const fileMatch = p.match(/^\/file\/([a-f0-9]{64}\.(?:jpg|jpeg|png|webp|heic|pdf))$/)
    if (fileMatch) {
      if (!authed(req)) return json(res, 401, { ok: false, error: 'not signed in' })
      const f = path.join(RECEIPT_DIR, fileMatch[1])
      if (!fs.existsSync(f)) return json(res, 404, { ok: false, error: 'not found' })
      res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'private, max-age=86400' })
      return res.end(fs.readFileSync(f))
    }

    // The generated bill, drawn fresh from the row so corrections show up immediately. Every
    // string in it is escaped in bill.render; the CSP is a second lock if one ever isn't.
    const billMatch = p.match(/^\/bill\/(\d+)\.svg$/)
    if (billMatch) {
      if (!authed(req)) return json(res, 401, { ok: false, error: 'not signed in' })
      const r = db.getReceipt(Number(billMatch[1]))
      if (!r) return json(res, 404, { ok: false, error: 'not found' })
      res.writeHead(200, { 'Content-Type': 'image/svg+xml', 'Cache-Control': 'no-store',
        'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'" })
      return res.end(bill.render(r))
    }

    const rel = p === '/' ? 'index.html' : p.replace(/^\/+/, '')
    const file = path.resolve(PUBLIC, rel)
    if (!file.startsWith(PUBLIC + path.sep)) return json(res, 403, { ok: false, error: 'forbidden' })
    if (!fs.existsSync(file) || !fs.statSync(file).isFile()) return json(res, 404, { ok: false, error: 'not found' })
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' })
    return res.end(fs.readFileSync(file))
  } catch (e) {
    console.error('[finance-web]', e)
    if (!res.headersSent) json(res, 500, { ok: false, error: String(e?.message || e) })
    else res.end()
  }
})
server.listen(PORT, HOST, () => {
  const s = db.stats()
  console.log(`[finance-web] listening on http://${HOST}:${PORT}`)
  console.log(`[finance-web] ${s.transactions} transactions · ${s.accounts} accounts · ${s.receipts} receipts`)
  for (const id of db.receiptsAwaitingBill()) queueBill(id)   // reads interrupted by a restart
  // The only process that ever calls Claude; everyone else just sets the refresh marker in the DB.
  if (process.env.LEDGER_SHOPPING_TIMER !== 'off') startShoppingTimer({ db })
})
