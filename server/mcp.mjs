// finance-mcp — personal finance tracker exposed as MCP tools over Streamable HTTP at /mcp.
// Bearer-token gated with a single token granting read + write. Deps are injected by
// index.cjs so this stays SDK-only.
//
// Deliberately absent: no raw-SQL tool, no execute/eval, no delete_all. A write-capable
// financial server reachable from the internet is the wrong place for a generic escape hatch.
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js'
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js'
import { z } from 'zod'
import crypto from 'node:crypto'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
import fx from './fx.cjs'

function tokenEqual(a, b) {
  const ab = Buffer.from(String(a ?? ''))
  const bb = Buffer.from(String(b ?? ''))
  return ab.length === bb.length && crypto.timingSafeEqual(ab, bb)
}

// ImageMagick: `magick` on Windows, whose own `convert.exe` is a disk tool; `convert` elsewhere (IM6 has no `magick`).
const IMAGEMAGICK = process.platform === 'win32' ? 'magick' : 'convert'
const p2 = (x) => String(x).padStart(2, '0')
const today = () => { const n = new Date(); return `${n.getFullYear()}-${p2(n.getMonth() + 1)}-${p2(n.getDate())}` }
const localNow = () => { const n = new Date(); return `${today()}T${p2(n.getHours())}:${p2(n.getMinutes())}:${p2(n.getSeconds())}` }
const shiftDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10) }
const monthStart = (d = today()) => d.slice(0, 8) + '01'
const nextMonth = (d = today()) => { const x = new Date(d.slice(0, 8) + '01T00:00:00Z'); x.setUTCMonth(x.getUTCMonth() + 1); return x.toISOString().slice(0, 10) }

const money = (c) => (c == null ? null : Math.round(c) / 100)
const ok = (o) => ({ content: [{ type: 'text', text: JSON.stringify(o ?? null, null, 2) }] })
const fail = (e) => ({ content: [{ type: 'text', text: 'Error: ' + (e?.message || e) }], isError: true })
const wrap = (fn) => async (a) => { try { return ok(await fn(a || {})) } catch (e) { return fail(e) } }

// Present money as both cents (exact, for machines) and a decimal (for humans/LLMs).
// Returning only a float invites the model to do arithmetic on it and reintroduce drift.
const fmtTx = (t) => ({
  id: t.id, posted_at: t.posted_at, account: t.account, direction: t.direction,
  amount: money(t.amount_cents), amount_cents: t.amount_cents, currency: t.currency,
  base_amount: money(t.base_amount_cents), base_currency: t.base_currency,
  category: t.category, subcategory: t.subcategory, merchant: t.merchant, note: t.note,
  source: t.source, reviewed: !!t.reviewed, confidence: t.confidence,
})

// A phone photo is 3-8 MB, which base64s to 4-11 MB of JSON — enough to blow up any agent's
// context for one receipt. Downscale before returning. ImageMagick is used opportunistically;
// without it we refuse oversized images rather than shipping the raw file.
const MAX_IMAGE_BYTES = 700_000

function loadReceiptImage(file, maxWidth = 1200) {
  const raw = fs.readFileSync(file)
  if (file.endsWith('.pdf')) return { pdf: true, bytes: raw.length }

  const mime = file.endsWith('.png') ? 'image/png' : file.endsWith('.webp') ? 'image/webp'
    : file.endsWith('.heic') ? 'image/heic' : 'image/jpeg'

  // Already small enough and in a format agents render: hand it back untouched.
  if (raw.length <= MAX_IMAGE_BYTES && mime !== 'image/heic') {
    return { data: raw.toString('base64'), mimeType: mime, bytes: raw.length, resized: false }
  }
  try {
    // -auto-orient because phone photos carry EXIF rotation the agent would otherwise read
    // sideways. JPEG out: a receipt is a photo, and PNG of a photo is larger, not sharper.
    const out = execFileSync(IMAGEMAGICK,
      [file + '[0]', '-auto-orient', '-resize', `${maxWidth}x${maxWidth}>`, '-quality', '72', 'jpeg:-'],
      { maxBuffer: 32 * 1024 * 1024, timeout: 20_000 })
    if (out.length > MAX_IMAGE_BYTES * 2) {
      return { tooLarge: true, bytes: raw.length, resizedBytes: out.length }
    }
    return { data: out.toString('base64'), mimeType: 'image/jpeg', bytes: raw.length, resizedBytes: out.length, resized: true }
  } catch (e) {
    if (raw.length <= MAX_IMAGE_BYTES) {
      return { data: raw.toString('base64'), mimeType: mime, bytes: raw.length, resized: false }
    }
    return { tooLarge: true, bytes: raw.length, error: String(e?.message || e).slice(0, 200) }
  }
}

const txInput = z.object({
  account: z.string().describe('Account name, e.g. "Checking", "Cash", "Visa card"'),
  posted_at: z.string().describe('ISO local datetime "YYYY-MM-DDTHH:MM:SS". The TIME matters — it is part of the dedup key, so same-day repeats stay distinct.'),
  direction: z.enum(['expense', 'income', 'transfer_in', 'transfer_out']),
  amount: z.number().optional().describe('Positive decimal amount. Direction carries the sign — never send a negative.'),
  amount_cents: z.number().int().optional().describe('Exact minor units. Preferred over `amount` when you have it.'),
  currency: z.string().optional().default('USD'),
  fx_rate: z.number().optional().describe('USD per 1 unit of currency; base = amount * fx_rate. Omit it: non-USD rows get the live ECB rate for posted_at.'),
  category: z.string().optional(),
  subcategory: z.string().optional(),
  merchant: z.string().optional().describe('Merchant name — the main signal for auto-categorization.'),
  note: z.string().optional(),
  counter_account: z.string().optional().describe('The other account, for transfers only.'),
  confidence: z.number().optional().describe('0-1, how sure you are of these figures.'),
})

export function buildServer(d) {
  const { db, categorize, reconcile } = d
  const s = new McpServer({ name: 'finance-mcp', version: '0.1.0' })
  const T = (name, desc, shape, fn) => s.tool(name, desc, shape, wrap(fn))
  // Single token grants everything, so write tools are always registered.
  const W = T

  // ===================== READ =====================

  T('get_status', 'Tracker status: transaction count, accounts, date range, write access.', {},
    async () => ({ app: 'finance-mcp', ...db.stats(), write_enabled: true }))

  T('list_accounts', 'All accounts with their implied current balance from the ledger.', {},
    async () => db.listAccounts().map((a) => {
      const tx = db.listTransactions({ account: a.name, limit: 100000 })
      return { name: a.name, kind: a.kind, currency: a.currency, transactions: tx.length,
               implied_balance: money(reconcile.impliedBalance(tx)) }
    }))

  T('list_transactions', 'Transactions in a date range, newest first. Dates are YYYY-MM-DD; `to` is exclusive.',
    { from: z.string().optional(), to: z.string().optional(), account: z.string().optional(),
      category: z.string().optional(), direction: z.enum(['expense', 'income', 'transfer_in', 'transfer_out']).optional(),
      limit: z.number().int().max(1000).optional() },
    async (a) => db.listTransactions({ ...a, limit: a.limit || 100 }).map(fmtTx))

  T('search_transactions', 'Free-text search across merchant, note, category and subcategory.',
    { q: z.string(), limit: z.number().int().max(200).optional() },
    async ({ q, limit }) => db.searchTransactions(q, limit || 50).map(fmtTx))

  T('spending_summary', 'Income, expense and net for a period. Transfers between your own accounts are EXCLUDED so they cannot inflate both sides.',
    { from: z.string().optional(), to: z.string().optional() },
    async ({ from, to }) => {
      const s2 = db.summary({ from: from || monthStart(), to: to || nextMonth() })
      return { ...s2, income: money(s2.income_cents), expense: money(s2.expense_cents), net: money(s2.net_cents) }
    })

  T('category_breakdown', 'Spend grouped by category for a period, largest first.',
    { from: z.string().optional(), to: z.string().optional(),
      direction: z.enum(['expense', 'income']).optional(), limit: z.number().int().max(100).optional() },
    async (a) => db.categoryBreakdown({ from: a.from || monthStart(), to: a.to || nextMonth(),
      direction: a.direction || 'expense', limit: a.limit || 20 })
      .map((r) => ({ category: r.category, count: r.n, total: money(r.cents), total_cents: r.cents })))

  T('budget_status', 'Budgets vs actual spend this month, worst overrun first.', {},
    async () => reconcile.budgetStatus({
      budgets: db.listBudgets(),
      spendByCategory: db.categoryBreakdown({ from: monthStart(), to: nextMonth(), direction: 'expense', limit: 200 })
        .map((r) => ({ category: r.category, cents: r.cents })),
      period_label: monthStart().slice(0, 7),
    }).map((b) => ({ ...b, limit: money(b.limit_cents), spent: money(b.spent_cents), remaining: money(b.remaining_cents) })))

  T('list_balances', 'Reported account balance snapshots (the anchor used for reconciliation).',
    { account: z.string().optional() },
    async ({ account }) => db.listBalances(account).map((b) => ({ ...b, balance: money(b.balance_cents) })))

  T('reconcile_account', 'Check whether the ledger explains the change between two reported balances. Non-zero drift means data is missing, duplicated, or invented.',
    { account: z.string(), from: z.string(), to: z.string() },
    async ({ account, from, to }) => {
      const snaps = db.listBalances(account).filter((b) => b.as_of_date >= from && b.as_of_date <= to)
        .sort((a, b) => a.as_of_date.localeCompare(b.as_of_date))
      if (snaps.length < 2) throw new Error(`need >=2 balance snapshots for ${account} between ${from} and ${to}; have ${snaps.length}. Use record_balance first.`)
      const open = snaps[0], close = snaps[snaps.length - 1]
      const tx = db.listTransactions({ account, from: open.as_of_date, to: close.as_of_date + 'T23:59:59', limit: 100000 })
      const r = reconcile.reconcileAccount({ account, from: open.as_of_date, to: close.as_of_date,
        opening_cents: open.balance_cents, closing_cents: close.balance_cents, transactions: tx })
      return { ...r, opening: money(r.opening_cents), closing: money(r.closing_cents),
               ledger_movement: money(r.ledger_movement_cents), drift: money(r.drift_cents) }
    })

  T('review_queue', 'Transactions written by an LLM that you have not confirmed yet. Review these before trusting any total.',
    { limit: z.number().int().max(500).optional() },
    async ({ limit }) => reconcile.reviewQueue(db.listTransactions({ limit: limit || 200 }))
      .map((r) => ({ ...r, amount: money(r.amount_cents) })))

  T('suggest_categories', 'Rule-based category suggestions for uncategorized rows. Returns suggestions only — nothing is written.',
    { limit: z.number().int().max(500).optional() },
    async ({ limit }) => {
      const rows = db.listTransactions({ limit: limit || 200 })
        .filter((r) => !r.category || r.category === 'Other')
      return categorize.suggestBatch(rows)
    })

  T('list_audit', 'Recent write operations against this tracker.',
    { limit: z.number().int().max(200).optional() },
    async ({ limit }) => db.listAudit(limit || 50))

  const fmtPriceItem = (p) => ({ ...p, min: money(p.min_cents), avg: money(p.avg_cents), max: money(p.max_cents),
    last: money(p.last_cents), prev: money(p.prev_cents), spent: money(p.spent_cents) })
  const fmtReceipt = (r) => {
    const file = db.receiptImageFile(r.image_path)
    return {
      id: r.id, merchant: r.merchant, purchased_at: r.purchased_at,
      total: money(r.total_cents), total_cents: r.total_cents,
      tax: money(r.tax_cents), currency: r.currency, source: r.source,
      transaction_id: r.transaction_id ?? null,
      line_items: r.line_items ?? null,
      // has_image says whether the bytes are actually on disk. add_receipt accepts an
      // image_path with nothing behind it, so image_path alone is not proof.
      has_image: !!file,
      image_bytes: file ? fs.statSync(file).size : null,
      image_path: r.image_path ?? null,
      // Photos uploaded in the web app are read into a bill automatically (server/bill.cjs).
      bill_status: r.bill_status ?? null,
      hint: file ? 'Call get_receipt_image to see the photo.' : undefined,
    }
  }

  T('list_receipts', 'Every stored receipt, newest first. Use `unattached_only` to find receipts not yet linked to a transaction. `has_image: true` means a photo is on disk and get_receipt_image can return it. Web uploads are read automatically: `bill_status` done means the bill exists; `line_items: null` with bill_status done is a split share of a purchase itemised on another receipt. Only when bill_status is failed or null with a photo: get_receipt_image, then set_receipt_items.',
    { limit: z.number().int().max(500).optional(),
      unattached_only: z.boolean().optional().describe('Only receipts with no transaction attached.') },
    async ({ limit, unattached_only }) =>
      db.listReceipts({ limit: limit || 100, unattached_only: !!unattached_only }).map(fmtReceipt))

  T('get_receipt', 'A stored receipt and the transaction it is attached to. `bill` is what Claude read off the photo on upload (printed merchant, items, tax, total, notes) — it can differ from the ledger fields when you booked only your share.',
    { id: z.number().int() },
    async ({ id }) => {
      const r = db.getReceipt(id)
      if (!r) throw new Error(`no receipt ${id}`)
      return { ...fmtReceipt(r), bill: r.bill_data, bill_error: r.bill_error ?? undefined,
               transaction: r.transaction ? fmtTx(r.transaction) : null }
    })

  // Returns the photo itself as an image content block, so a vision-capable agent can read
  // the receipt rather than trusting fields someone typed in.
  s.tool('get_receipt_image',
    'The actual receipt photo, returned as an image you can read. Use it to verify or extract line items, tax and totals from the original rather than relying on transcribed fields. Large photos are downscaled before sending.',
    { id: z.number().int(), max_width: z.number().int().min(200).max(2400).optional().describe('Longest edge in pixels. Default 1200.') },
    async ({ id, max_width }) => {
      try {
        const r = db.getReceipt(id)
        if (!r) return fail(`no receipt ${id}`)
        const file = db.receiptImageFile(r.image_path)
        if (!file) {
          return fail(r.image_path
            ? `receipt ${id} references "${r.image_path}" but that file is not on disk — it was recorded without an upload`
            : `receipt ${id} has no image; only its typed fields were stored`)
        }
        const img = loadReceiptImage(file, max_width || 1200)
        if (img.pdf) return fail(`receipt ${id} is a PDF (${Math.round(img.bytes / 1024)} KB), which cannot be returned as an image`)
        if (img.tooLarge) return fail(`receipt ${id} image is ${(img.bytes / 1048576).toFixed(1)} MB and could not be reduced enough to send`)
        return {
          content: [
            { type: 'text', text: JSON.stringify({ receipt_id: id, merchant: r.merchant, purchased_at: r.purchased_at,
              total: money(r.total_cents), original_bytes: img.bytes, sent_bytes: img.resizedBytes ?? img.bytes, downscaled: !!img.resized }) },
            { type: 'image', data: img.data, mimeType: img.mimeType },
          ],
        }
      } catch (e) { return fail(e) }
    })

  // ===================== WRITE =====================

  W('upsert_transactions', 'Add or update transactions. IDEMPOTENT — re-sending the same rows updates instead of duplicating, so it is safe to re-sync overlapping date ranges. Send amounts as POSITIVE; `direction` carries the sign.',
    { items: z.array(txInput).max(500).describe('Up to 500 transactions per call.'),
      source: z.string().optional().describe('Where these came from, e.g. "chatgpt".') },
    async ({ items, source }) => {
      const res = db.upsertTransactions(await fx.fillRates(items, db), { source: source || 'chatgpt', actor: 'mcp' })
      return { ...res, note: res.errors.length ? 'Some rows failed; see errors[].' : 'All rows written.' }
    })

  W('record_balance', 'Record a reported account balance for a date. Used as the independent anchor for reconciliation.',
    { account: z.string(), as_of_date: z.string(), balance: z.number().optional(),
      balance_cents: z.number().int().optional(), currency: z.string().optional() },
    async (a) => {
      const c = a.balance_cents != null ? a.balance_cents : db.toCents(a.balance)
      if (c == null) throw new Error('balance or balance_cents required')
      return db.recordBalance({ account: a.account, as_of_date: a.as_of_date, balance_cents: c, currency: a.currency || 'USD' })
    })

  W('add_receipt', 'Store a receipt you extracted from an image and auto-attach it to a matching transaction (same-ish date, amount within 2%). Send the STRUCTURED fields, not the image.',
    { merchant: z.string().optional(), purchased_at: z.string().optional(),
      total: z.number().optional(), total_cents: z.number().int().optional(),
      tax: z.number().optional(), currency: z.string().optional(),
      line_items: z.array(z.object({ name: z.string(), qty: z.number().optional(), price: z.number().optional() })).optional(),
      transaction_id: z.number().int().optional() },
    async (a) => {
      const total_cents = a.total_cents != null ? a.total_cents : db.toCents(a.total)
      let txId = a.transaction_id ?? null
      let matched = null
      if (!txId) {
        matched = db.matchReceiptToTransaction({ total_cents, purchased_at: a.purchased_at })
        txId = matched?.id ?? null
      }
      const r = db.addReceipt({ ...a, total_cents, tax_cents: db.toCents(a.tax), transaction_id: txId })
      return { ...r, matched_transaction: matched ? fmtTx(matched) : null,
               note: txId ? 'Attached to a transaction.' : 'No confident match — receipt stored unattached for review.' }
    })

  T('item_prices', 'Price tracking: every grocery item seen on stored receipts, grouped by normalised name + unit, with how often it was bought, min/avg/max unit price, the latest price and % change vs the previous purchase. Filter with `q` (substring) or `merchant`.',
    { q: z.string().optional(), merchant: z.string().optional(), limit: z.number().int().max(500).optional() },
    async ({ q, merchant, limit }) => db.priceItems({ q, merchant, limit: limit || 200 }).map(fmtPriceItem))

  T('item_price_history', 'Every purchase of one item, oldest first — date, merchant, qty, unit price, line total. Use the `item_key` from item_prices.',
    { item_key: z.string(),
      unit: z.string().optional().describe('each | lb | oz | gal … — narrows to one unit when an item was bought both ways.') },
    async ({ item_key, unit }) => db.priceHistory(item_key, { unit })
      .map((h) => ({ ...h, unit_price: money(h.unit_price_cents), total: money(h.total_cents) })))

  T('inventory', 'What is in the house, estimated from receipts: one row per item + unit with `status` (learning | in_stock | running_low | used_up | lapsed | off | once), last bought, `qty_left`, `used_pct`, `days_left`, and the last price. Quantities are in the item `unit` (each | lb | oz | gal …). Only items bought on 2+ days are tracked automatically; `include_untracked: true` also returns lapsed, off and once-only items. Filter with `q` (substring) or `status`.',
    { q: z.string().optional(),
      status: z.enum(['learning', 'in_stock', 'running_low', 'used_up', 'lapsed', 'off', 'once']).optional(),
      include_untracked: z.boolean().optional() },
    async ({ q, status, include_untracked }) => db.inventory({ q, status, include_untracked, today: today() })
      .map((i) => ({ ...i, last_price: money(i.last_price_cents) })))

  T('shopping_list', 'The open shopping list: items with qty, why they are on it (`source`: user | ai | rule, plus `reason`), the last price paid and the cheapest recent merchant, and the estimated `total`. `ai` says when Claude last refreshed the list and whether a refresh is pending.',
    {},
    async () => {
      const l = db.shoppingList({ today: today() })
      return { ...l, total: money(l.total_cents), items: l.items.map((i) => ({ ...i, last_price: money(i.last_price_cents) })) }
    })

  W('set_receipt_items', 'Replace the line items on a stored receipt — use after reading its photo with get_receipt_image (receipts uploaded from the web app have a photo but no items until someone reads it). Write weighed produce as "Red onion — 3.53 lb @ $0.59/lb" and pack sizes as "Rice 20 lb" / "Yogurt 48 oz" so a per-unit price is derived; qty is the number of packs.',
    { id: z.number().int(),
      line_items: z.array(z.object({ name: z.string(), qty: z.number().optional(), price: z.number().optional() })),
      tax: z.number().optional() },
    async ({ id, line_items, tax }) => {
      const n = db.setReceiptItems(id, line_items, { tax_cents: tax != null ? db.toCents(tax) : undefined })
      if (n == null) throw new Error(`no receipt ${id}`)
      return { id, items: n }
    })

  W('mark_used_up', 'Say an item ran out ("Used up") — the routine input that teaches the household estimate how fast it goes through that item. `item_key` comes from inventory; `unit` narrows it when the item was bought in two units; `date` is YYYY-MM-DD, default today.',
    { item_key: z.string(), unit: z.string().optional(), date: z.string().optional() },
    async ({ item_key, unit, date }) => db.markUsedUp({ item_key, unit, at: date || today(), actor: 'mcp' }))

  W('set_item_tracking', 'Override whether an item is tracked in inventory. `tracked: true` always tracks it, `false` hides it, `null` goes back to automatic (tracked once bought on 2+ days). `item_key` and `unit` come from inventory.',
    { item_key: z.string(), unit: z.string(), tracked: z.boolean().nullable() },
    async ({ item_key, unit, tracked }) => db.setItemTracking({ item_key, unit, tracked, actor: 'mcp' }))

  W('update_shopping_list', 'Change the shopping list; ids come from shopping_list. `add` puts items on it as the owner\'s own (`qty` optional); `bought` ticks items off as bought today (counts as a restock); `dismiss` closes Claude/rule suggestions and `remove` closes the owner\'s own items. Each id list only affects rows it fits, so a mismatch is skipped, not an error.',
    { add: z.array(z.object({ name: z.string(), qty: z.number().optional() })).max(100).optional(),
      bought: z.array(z.number().int()).max(200).optional(),
      dismiss: z.array(z.number().int()).max(200).optional(),
      remove: z.array(z.number().int()).max(200).optional() },
    async ({ add, bought, dismiss, remove }) => db.updateShoppingList({ add, bought, dismiss, remove, actor: 'mcp', today: today() }))

  W('refresh_shopping_list', 'Ask for Claude to review the shopping list. This only queues the request: the server runs it within a minute, so call shopping_list afterwards and check `ai.pending` and `ai.last_run_at`.',
    {},
    async () => db.requestShoppingRefresh())

  W('set_category', 'Set the category (and optionally subcategory) on one transaction.',
    { id: z.number().int(), category: z.string(), subcategory: z.string().optional() },
    async ({ id, category, subcategory }) => fmtTx(db.setCategory(id, category, subcategory)))

  W('mark_reviewed', 'Confirm LLM-written transactions after you have checked them.',
    { ids: z.array(z.number().int()).max(500) },
    async ({ ids }) => db.markReviewed(ids))

  W('void_transaction', 'Soft-delete a transaction (e.g. a duplicate). The row is retained and hidden, never destroyed.',
    { id: z.number().int(), reason: z.string().optional() },
    async ({ id, reason }) => db.voidTransaction(id, reason))

  W('set_budget', 'Set a monthly or weekly spending limit for a category. Category "Total" sets the overall limit across ALL spending.',
    { category: z.string(), period: z.enum(['monthly', 'weekly']).optional(),
      limit: z.number().optional(), limit_cents: z.number().int().optional() },
    async (a) => {
      const c = a.limit_cents != null ? a.limit_cents : db.toCents(a.limit)
      if (c == null) throw new Error('limit or limit_cents required')
      return db.setBudget({ category: a.category, period: a.period || 'monthly', limit_cents: c })
    })

  return s
}

// ONE token, granting read + write. A read/write split was considered and dropped: both
// tokens would live in the same .data/ dir and be pasted into the same class of cloud
// connector, so the split only defended the narrow case of "read client compromised, write
// client not" — while doubling the secrets to manage. A leaked read token is arguably the
// worse outcome anyway (it exposes every transaction), and writes are soft-deleted +
// audited. Not worth the friction for a single-user tracker.
export function createMcpHandler(deps) {
  const { token } = deps
  return async function handleMcp(req, res, bodyRaw) {
    const authz = req.headers['authorization'] || ''
    // ?token= is accepted because the Claude/ChatGPT connector dialogs have no header field,
    // so a single URL is the only way to configure them. It is strictly worse than a header:
    // URLs land in proxy logs, browser history and screenshots. Prefer the Authorization
    // header wherever the client allows one — this fallback exists for the ones that don't.
    const qs = req.url && req.url.includes('?') ? new URLSearchParams(req.url.slice(req.url.indexOf('?') + 1)) : null
    const provided = authz.startsWith('Bearer ') ? authz.slice(7)
      : (req.headers['x-api-key'] || (qs && qs.get('token')) || '')
    const isWrite = token && tokenEqual(provided, token)
    if (!isWrite) {
      res.writeHead(401, { 'Content-Type': 'application/json', 'WWW-Authenticate': 'Bearer realm="finance-mcp"' })
      return res.end(JSON.stringify({ jsonrpc: '2.0', error: { code: -32001, message: 'Unauthorized: bearer token required in the Authorization header' }, id: null }))
    }
    const server = buildServer(deps)
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true })
    res.on('close', () => { transport.close(); server.close() })
    let body
    if (bodyRaw) { try { body = JSON.parse(bodyRaw) } catch { /* let the transport 400 it */ } }
    await server.connect(transport)
    await transport.handleRequest(req, res, body)
  }
}
