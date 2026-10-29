// finance-mcp storage layer. node:sqlite, no ORM — same shape as health-mcp/server/db.cjs.
//
// Two rules this schema exists to enforce:
//   1. Money is INTEGER minor units (cents). Never a float. The source export already
//      carries artifacts like 79.34999999999999; storing that as REAL compounds it.
//   2. Every write is an idempotent upsert keyed on `external_id`. ChatGPT re-reads
//      overlapping date ranges every time it syncs, so blind INSERT means silent
//      double-counting of real money.
const { DatabaseSync } = require('node:sqlite')
const path = require('node:path')
const fs = require('node:fs')
const crypto = require('node:crypto')
const { toStoredLine } = require('./bill.cjs')
const { isProductLine, estimateItem, dayNum } = require('./inventory.cjs')
const { ruleSuggestions, clip, cleanQty, NAME_MAX, REASON_MAX, MAX_AI_ADDS } = require('./shopping.cjs')

let db = null
let dbFile = null

const DEFAULT_DB = path.join(__dirname, '..', '.data', 'finance.sqlite')

// Receipt images live beside whichever database is open, so both processes agree on the
// location and pointing FINANCE_DB at a copy keeps a test run's uploads out of real data.
const receiptDir = () => path.join(path.dirname(dbFile || process.env.FINANCE_DB || DEFAULT_DB), 'receipts')

// Resolve a stored image_path to a real file. Names are content hashes written by the web
// uploader; anything else (or a missing file) returns null rather than reaching the disk.
function receiptImageFile(name) {
  if (!name || !/^[a-f0-9]{64}\.(jpg|jpeg|png|webp|heic|pdf)$/.test(name)) return null
  const f = path.join(receiptDir(), name)
  return fs.existsSync(f) ? f : null
}

function initDb(file = process.env.FINANCE_DB || DEFAULT_DB) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  dbFile = file
  db = new DatabaseSync(file)
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;
    -- Two processes now open this file: the MCP server and the web UI. WAL already allows
    -- concurrent readers alongside one writer; busy_timeout makes the loser of a write race
    -- wait for the lock instead of throwing SQLITE_BUSY at whoever asked second.
    PRAGMA busy_timeout = 5000;

    CREATE TABLE IF NOT EXISTS accounts (
      id          INTEGER PRIMARY KEY,
      name        TEXT NOT NULL UNIQUE,
      kind        TEXT,               -- checking | credit | cash | wallet | virtual
      institution TEXT,
      currency    TEXT NOT NULL DEFAULT 'USD',
      archived    INTEGER NOT NULL DEFAULT 0,
      created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    );

    -- amount_cents is ALWAYS positive; direction carries the sign meaning. Mixing the two
    -- (negative = expense) makes transfers and refunds ambiguous.
    CREATE TABLE IF NOT EXISTS transactions (
      id            INTEGER PRIMARY KEY,
      account_id    INTEGER NOT NULL REFERENCES accounts(id),
      posted_at     TEXT NOT NULL,     -- ISO local 'YYYY-MM-DDTHH:MM:SS'
      direction     TEXT NOT NULL CHECK (direction IN ('expense','income','transfer_in','transfer_out')),
      amount_cents  INTEGER NOT NULL CHECK (amount_cents >= 0),
      currency      TEXT NOT NULL DEFAULT 'USD',
      -- Multi-currency: base_amount_cents is amount_cents converted to base_currency at
      -- fx_rate. For same-currency rows fx_rate is 1 and the two amounts match.
      fx_rate       REAL NOT NULL DEFAULT 1.0,
      base_currency TEXT NOT NULL DEFAULT 'USD',
      base_amount_cents INTEGER NOT NULL,
      category      TEXT,
      subcategory   TEXT,
      merchant      TEXT,
      note          TEXT,
      counter_account_id INTEGER REFERENCES accounts(id),  -- other leg of a transfer
      source        TEXT NOT NULL DEFAULT 'manual',        -- manual | import | chatgpt | receipt
      confidence    REAL,
      reviewed      INTEGER NOT NULL DEFAULT 0,
      voided_at     TEXT,                                   -- soft delete; never hard-delete money
      external_id   TEXT NOT NULL UNIQUE,
      created_at    TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS ix_tx_posted   ON transactions(posted_at);
    CREATE INDEX IF NOT EXISTS ix_tx_account  ON transactions(account_id, posted_at);
    CREATE INDEX IF NOT EXISTS ix_tx_category ON transactions(category);

    CREATE TABLE IF NOT EXISTS receipts (
      id             INTEGER PRIMARY KEY,
      transaction_id INTEGER REFERENCES transactions(id),
      merchant       TEXT,
      purchased_at   TEXT,
      total_cents    INTEGER,
      tax_cents      INTEGER,
      currency       TEXT NOT NULL DEFAULT 'USD',
      line_items     TEXT,             -- JSON array
      image_path     TEXT,
      source         TEXT NOT NULL DEFAULT 'chatgpt',
      external_id    TEXT NOT NULL UNIQUE,
      created_at     TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS balances (
      account_id    INTEGER NOT NULL REFERENCES accounts(id),
      as_of_date    TEXT NOT NULL,
      balance_cents INTEGER NOT NULL,
      currency      TEXT NOT NULL DEFAULT 'USD',
      PRIMARY KEY (account_id, as_of_date)
    );

    CREATE TABLE IF NOT EXISTS budgets (
      id          INTEGER PRIMARY KEY,
      category    TEXT NOT NULL,
      period      TEXT NOT NULL,        -- 'monthly' | 'weekly'
      limit_cents INTEGER NOT NULL,
      currency    TEXT NOT NULL DEFAULT 'USD',
      UNIQUE (category, period)
    );

    -- Every write is logged. Non-negotiable for money reachable from the internet.
    -- One row per receipt line. receipts.line_items (JSON) stays the write-side source so
    -- add_receipt's contract is unchanged; this table is DERIVED from it by syncReceiptItems,
    -- and exists so "what has chicken breast cost me over time" is one indexed query instead
    -- of parsing every receipt's JSON. merchant/purchased_at are copied down for that reason.
    CREATE TABLE IF NOT EXISTS receipt_items (
      id               INTEGER PRIMARY KEY,
      receipt_id       INTEGER NOT NULL REFERENCES receipts(id),
      line_no          INTEGER NOT NULL,
      name             TEXT NOT NULL,      -- as printed / extracted
      item_key         TEXT NOT NULL,      -- normalised: lowercase, weights and pack sizes stripped
      qty              REAL NOT NULL DEFAULT 1,
      unit             TEXT NOT NULL DEFAULT 'each',   -- each | lb | oz | kg | g | l | ml | gal
      unit_price_cents INTEGER,            -- price per unit; NULL if it could not be derived
      total_cents      INTEGER NOT NULL,
      merchant         TEXT,
      purchased_at     TEXT,
      UNIQUE (receipt_id, line_no)
    );
    CREATE INDEX IF NOT EXISTS receipt_items_key ON receipt_items(item_key, purchased_at);

    -- Inventory + shopping list (see inventory.cjs). Both are keyed on receipt_items' (item_key, unit).
    CREATE TABLE IF NOT EXISTS item_settings (
      item_key TEXT NOT NULL, unit TEXT NOT NULL,
      tracked  INTEGER,                         -- NULL = auto (2+ purchase days), 1 = on, 0 = off
      PRIMARY KEY (item_key, unit)
    );
    CREATE TABLE IF NOT EXISTS item_events (
      id INTEGER PRIMARY KEY, item_key TEXT NOT NULL, unit TEXT NOT NULL,
      kind TEXT NOT NULL CHECK (kind = 'used_up'),
      at   TEXT NOT NULL, actor TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    -- close_event_id / close_receipt_id: the newest item_events / receipts id when the row was
    -- closed, so "new information since" never depends on clocks. restock_date: set only when the
    -- owner ticks a row bought with no receipt; inventory() counts it as a rebuy on that day.
    CREATE TABLE IF NOT EXISTS shopping_list (
      id INTEGER PRIMARY KEY, item_key TEXT, unit TEXT, name TEXT NOT NULL, qty REAL,
      source TEXT NOT NULL CHECK (source IN ('rule','ai','user')),
      reason TEXT,
      status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','bought','dismissed','removed')),
      created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT, closed_at TEXT,
      close_event_id INTEGER, close_receipt_id INTEGER, restock_date TEXT
    );
    CREATE TABLE IF NOT EXISTS shopping_state (
      id INTEGER PRIMARY KEY CHECK (id = 1), requested_at TEXT, running_since TEXT, last_run_at TEXT,
      last_ok INTEGER, last_message TEXT, last_marker TEXT
    );
    INSERT OR IGNORE INTO shopping_state (id) VALUES (1);   -- the single state row always exists

    CREATE TABLE IF NOT EXISTS audit_log (
      id         INTEGER PRIMARY KEY,
      ts         TEXT NOT NULL DEFAULT (datetime('now')),
      tool       TEXT NOT NULL,
      actor      TEXT,
      args_hash  TEXT,
      affected   INTEGER,
      detail     TEXT
    );
  `)
  // Generated bills (server/bill.cjs). bill_data is what Claude read off the photo, kept apart
  // from the ledger's own fields: a receipt booked at your share of a split still shows the
  // full printed bill. bill_status: pending | reading | done | failed.
  const rcols = new Set(db.prepare('PRAGMA table_info(receipts)').all().map((c) => c.name))
  for (const col of ['bill_status', 'bill_error', 'bill_data']) {
    // the web and MCP processes can start together and race to add it; losing that race is fine
    if (!rcols.has(col)) try { db.exec(`ALTER TABLE receipts ADD COLUMN ${col} TEXT`) } catch (e) { if (!/duplicate column/.test(e.message)) throw e }
  }
  // Backfill receipt_items for receipts that predate the table. Idempotent: only receipts
  // with line_items and zero derived rows are touched.
  for (const r of db.prepare(`SELECT id FROM receipts WHERE line_items IS NOT NULL
                              AND id NOT IN (SELECT DISTINCT receipt_id FROM receipt_items)`).all()) {
    syncReceiptItems(r.id)
  }
  return db
}

const conn = () => db || initDb()

// ---- helpers -------------------------------------------------------------

// Cents from a possibly float-noisy string/number. 79.34999999999999 -> 7935.
function toCents(v) {
  if (v == null || v === '') return null
  const n = typeof v === 'number' ? v : Number(String(v).replace(/[, ]/g, ''))
  if (!Number.isFinite(n)) return null
  return Math.round(n * 100)
}

// Natural key. Includes the FULL timestamp: the source data has 8 legitimate same-day,
// same-amount repeats (two $5 transport fares on one day) that a date-only key would
// collapse into one, silently deleting real spending.
function externalId({ account, posted_at, amount_cents, currency, direction }) {
  const s = [account, posted_at, amount_cents, currency || 'USD', direction].join('|')
  return crypto.createHash('sha256').update(s).digest('hex').slice(0, 32)
}

// ---- accounts ------------------------------------------------------------

function upsertAccount({ name, kind = null, institution = null, currency = 'USD' }) {
  const c = conn()
  c.prepare(`INSERT INTO accounts (name, kind, institution, currency) VALUES (?,?,?,?)
             ON CONFLICT(name) DO UPDATE SET
               kind=COALESCE(excluded.kind, accounts.kind),
               institution=COALESCE(excluded.institution, accounts.institution)`)
    .run(name, kind, institution, currency)
  return c.prepare('SELECT * FROM accounts WHERE name = ?').get(name)
}
// Archived accounts (e.g. a card merged into its replacement) stay in the table so their
// history and foreign keys survive, but they are not live accounts and must not appear in
// balances, pickers or net worth. Pass { archived: true } only when you genuinely need them.
const listAccounts = ({ archived = false } = {}) =>
  conn().prepare(archived ? 'SELECT * FROM accounts ORDER BY name'
                          : 'SELECT * FROM accounts WHERE archived = 0 ORDER BY name').all()
const accountByName = (name) => conn().prepare('SELECT * FROM accounts WHERE name = ?').get(name) || null

// ---- transactions --------------------------------------------------------

function upsertTransaction(t) {
  const c = conn()
  const acct = accountByName(t.account) || upsertAccount({ name: t.account })
  const cents = t.amount_cents != null ? t.amount_cents : toCents(t.amount)
  if (cents == null) throw new Error(`amount missing/invalid for ${t.account} ${t.posted_at}`)
  if (cents < 0) throw new Error('amount must be positive; use direction for sign')
  const currency = t.currency || acct.currency || 'USD'
  const base_currency = t.base_currency || 'USD'
  const fx = t.fx_rate != null ? t.fx_rate : (currency === base_currency ? 1.0 : null)
  if (fx == null) throw new Error(`fx_rate required converting ${currency} -> ${base_currency}`)
  const base_cents = t.base_amount_cents != null ? t.base_amount_cents : Math.round(cents * fx)
  const counter = t.counter_account ? (accountByName(t.counter_account) || upsertAccount({ name: t.counter_account })).id : null
  const ext = t.external_id || externalId({ account: acct.name, posted_at: t.posted_at, amount_cents: cents, currency, direction: t.direction })

  const before = c.prepare('SELECT id FROM transactions WHERE external_id = ?').get(ext)
  c.prepare(`INSERT INTO transactions
      (account_id, posted_at, direction, amount_cents, currency, fx_rate, base_currency,
       base_amount_cents, category, subcategory, merchant, note, counter_account_id,
       source, confidence, reviewed, external_id)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
     ON CONFLICT(external_id) DO UPDATE SET
       category    = COALESCE(excluded.category, transactions.category),
       subcategory = COALESCE(excluded.subcategory, transactions.subcategory),
       merchant    = COALESCE(excluded.merchant, transactions.merchant),
       note        = COALESCE(excluded.note, transactions.note),
       counter_account_id = COALESCE(excluded.counter_account_id, transactions.counter_account_id),
       confidence  = COALESCE(excluded.confidence, transactions.confidence),
       updated_at  = datetime('now')`)
    .run(acct.id, t.posted_at, t.direction, cents, currency, fx, base_currency, base_cents,
         t.category ?? null, t.subcategory ?? null, t.merchant ?? null, t.note ?? null,
         counter, t.source || 'manual', t.confidence ?? null, t.reviewed ? 1 : 0, ext)
  // Return the id: the caller needs it to attach a receipt to the row it just created.
  const after = c.prepare('SELECT id FROM transactions WHERE external_id = ?').get(ext)
  return { id: after.id, external_id: ext, inserted: !before, updated: !!before }
}

function upsertTransactions(items, { source = 'manual', actor = null } = {}) {
  const c = conn()
  let inserted = 0, updated = 0
  const errors = []
  const ids = []
  c.exec('BEGIN')
  try {
    for (const [i, raw] of items.entries()) {
      try {
        const r = upsertTransaction({ ...raw, source: raw.source || source })
        r.inserted ? inserted++ : updated++
        ids.push(r.id)
      } catch (e) { errors.push({ index: i, error: e.message }) }
    }
    c.exec('COMMIT')
  } catch (e) { c.exec('ROLLBACK'); throw e }
  audit('upsert_transactions', actor, { count: items.length }, inserted + updated,
        errors.length ? `${errors.length} error(s)` : null)
  return { inserted, updated, errors, ids }
}

// `q` and `offset` exist for the web UI's paged, filterable table. The MCP tools never pass
// them, so their defaults keep every existing caller on the old behaviour.
function txWhere({ from, to, account, category, direction, q, reviewed, include_voided = false }) {
  const w = [], p = []
  if (from) { w.push('t.posted_at >= ?'); p.push(from) }
  if (to) { w.push('t.posted_at < ?'); p.push(to) }
  if (account) { w.push('a.name = ?'); p.push(account) }
  if (category) { w.push(category === '(uncategorized)' ? 't.category IS NULL' : 't.category = ?'); if (category !== '(uncategorized)') p.push(category) }
  if (direction) { w.push('t.direction = ?'); p.push(direction) }
  if (reviewed === 0 || reviewed === 1) { w.push('t.reviewed = ?'); p.push(reviewed) }
  if (q) {
    w.push('(t.merchant LIKE ? OR t.note LIKE ? OR t.category LIKE ? OR t.subcategory LIKE ?)')
    const like = `%${q}%`; p.push(like, like, like, like)
  }
  if (!include_voided) w.push('t.voided_at IS NULL')
  return { clause: w.length ? 'WHERE ' + w.join(' AND ') : '', params: p }
}

function listTransactions(o = {}) {
  const { clause, params } = txWhere(o)
  const sql = `SELECT t.*, a.name AS account FROM transactions t JOIN accounts a ON a.id = t.account_id
               ${clause} ORDER BY t.posted_at DESC LIMIT ? OFFSET ?`
  return conn().prepare(sql).all(...params, o.limit ?? 200, o.offset ?? 0)
}

function countTransactions(o = {}) {
  const { clause, params } = txWhere(o)
  return conn().prepare(`SELECT COUNT(*) n FROM transactions t JOIN accounts a ON a.id = t.account_id ${clause}`)
    .get(...params).n
}

function searchTransactions(q, limit = 50) {
  const like = `%${q}%`
  return conn().prepare(
    `SELECT t.*, a.name AS account FROM transactions t JOIN accounts a ON a.id = t.account_id
     WHERE t.voided_at IS NULL AND (t.merchant LIKE ? OR t.note LIKE ? OR t.category LIKE ? OR t.subcategory LIKE ?)
     ORDER BY t.posted_at DESC LIMIT ?`).all(like, like, like, like, limit)
}

// Transfers are excluded: they move money between your own accounts and would otherwise
// inflate both income and expense (the source export has 8 pairs totalling $4,454 each way).
function summary({ from, to } = {}) {
  const w = ["voided_at IS NULL"], p = []
  if (from) { w.push('posted_at >= ?'); p.push(from) }
  if (to) { w.push('posted_at < ?'); p.push(to) }
  const rows = conn().prepare(
    `SELECT direction, COUNT(*) n, SUM(base_amount_cents) cents
     FROM transactions WHERE ${w.join(' AND ')} GROUP BY direction`).all(...p)
  const by = Object.fromEntries(rows.map((r) => [r.direction, { count: r.n, cents: r.cents }]))
  const income = by.income?.cents || 0
  const expense = by.expense?.cents || 0
  return {
    from: from ?? null, to: to ?? null,
    income_cents: income, expense_cents: expense, net_cents: income - expense,
    transfers_excluded: (by.transfer_in?.count || 0) + (by.transfer_out?.count || 0),
    by_direction: by,
  }
}

function categoryBreakdown({ from, to, direction = 'expense', limit = 30 } = {}) {
  const w = ['voided_at IS NULL', 'direction = ?'], p = [direction]
  if (from) { w.push('posted_at >= ?'); p.push(from) }
  if (to) { w.push('posted_at < ?'); p.push(to) }
  return conn().prepare(
    `SELECT COALESCE(category,'(uncategorized)') category, COUNT(*) n, SUM(base_amount_cents) cents
     FROM transactions WHERE ${w.join(' AND ')} GROUP BY category ORDER BY cents DESC LIMIT ?`).all(...p, limit)
}

function setCategory(id, category, subcategory = null) {
  conn().prepare(`UPDATE transactions SET category=?, subcategory=COALESCE(?,subcategory),
                  updated_at=datetime('now') WHERE id=?`).run(category, subcategory, id)
  audit('set_category', null, { id, category }, 1)
  return conn().prepare('SELECT * FROM transactions WHERE id=?').get(id)
}

function markReviewed(ids) {
  const c = conn(); let n = 0
  for (const id of ids) n += c.prepare("UPDATE transactions SET reviewed=1, updated_at=datetime('now') WHERE id=?").run(id).changes
  audit('mark_reviewed', null, { ids }, n)
  return { updated: n }
}

function voidTransaction(id, reason = null) {
  const n = conn().prepare("UPDATE transactions SET voided_at=datetime('now'), note=COALESCE(note,'')||? WHERE id=? AND voided_at IS NULL")
    .run(reason ? ` [voided: ${reason}]` : ' [voided]', id).changes
  audit('void_transaction', null, { id, reason }, n)
  return { voided: n }
}

// Editable fields are exactly those NOT in the external_id key. Amount, date, account and
// direction are the natural key — changing one would orphan the row from every future
// re-sync of the same data. Correct those with void + re-add, not an UPDATE.
const EDITABLE = ['category', 'subcategory', 'merchant', 'note']

function updateTransaction(id, fields) {
  const set = [], p = []
  for (const k of EDITABLE) if (k in fields) { set.push(`${k}=?`); p.push(fields[k] === '' ? null : fields[k]) }
  if (!set.length) throw new Error(`nothing to update; editable fields are ${EDITABLE.join(', ')}`)
  const n = conn().prepare(`UPDATE transactions SET ${set.join(', ')}, updated_at=datetime('now') WHERE id=?`)
    .run(...p, id).changes
  audit('update_transaction', null, { id, fields: Object.keys(fields) }, n)
  return conn().prepare('SELECT t.*, a.name account FROM transactions t JOIN accounts a ON a.id=t.account_id WHERE t.id=?').get(id)
}

// Spend/income per calendar month, oldest first — the shape the trend chart wants.
function monthlySeries({ months = 12 } = {}) {
  return conn().prepare(
    `SELECT substr(posted_at,1,7) month,
            SUM(CASE WHEN direction='expense' THEN base_amount_cents ELSE 0 END) expense_cents,
            SUM(CASE WHEN direction='income'  THEN base_amount_cents ELSE 0 END) income_cents,
            COUNT(*) n
     FROM transactions WHERE voided_at IS NULL AND direction IN ('expense','income')
     GROUP BY month ORDER BY month DESC LIMIT ?`).all(months).reverse()
}

const getTransaction = (id) => conn().prepare(
  'SELECT t.*, a.name account FROM transactions t JOIN accounts a ON a.id=t.account_id WHERE t.id=?').get(id) || null

const receiptsForTransaction = (id) => conn().prepare('SELECT * FROM receipts WHERE transaction_id=? ORDER BY id DESC').all(id)
  .map((r) => ({ ...r, line_items: r.line_items ? JSON.parse(r.line_items) : null }))

// Per-category rollup across every direction, for the Categories view. categoryBreakdown()
// answers a narrower question (spend in one direction) and is kept as-is for the MCP tool.
function categoryStats({ from, to } = {}) {
  const w = ['voided_at IS NULL'], p = []
  if (from) { w.push('posted_at >= ?'); p.push(from) }
  if (to) { w.push('posted_at < ?'); p.push(to) }
  return conn().prepare(
    `SELECT COALESCE(category,'(uncategorized)') category, COUNT(*) n,
            SUM(CASE WHEN direction='expense' THEN base_amount_cents ELSE 0 END) expense_cents,
            SUM(CASE WHEN direction='income'  THEN base_amount_cents ELSE 0 END) income_cents,
            MAX(posted_at) last_used
     FROM transactions WHERE ${w.join(' AND ')}
     GROUP BY COALESCE(category,'(uncategorized)') ORDER BY expense_cents DESC, n DESC`).all(...p)
}

// Bulk rename. 47% of the imported history sits in "Other", so moving a whole category at
// once is the only practical way to clean it up — one row at a time would take all day.
function renameCategory(from, to) {
  const n = conn().prepare(`UPDATE transactions SET category=?, updated_at=datetime('now')
                            WHERE category IS ? AND voided_at IS NULL`)
    .run(to || null, from === '(uncategorized)' ? null : from).changes
  audit('rename_category', null, { from, to }, n)
  return { renamed: n, from, to }
}

const distinctCategories = () => conn().prepare(
  `SELECT DISTINCT category FROM transactions WHERE category IS NOT NULL AND voided_at IS NULL ORDER BY category`)
  .all().map((r) => r.category)

const listReceipts = ({ limit = 100, unattached_only = false } = {}) => conn().prepare(
  `SELECT r.*, t.posted_at tx_posted_at, a.name tx_account
   FROM receipts r LEFT JOIN transactions t ON t.id = r.transaction_id
                   LEFT JOIN accounts a ON a.id = t.account_id
   ${unattached_only ? 'WHERE r.transaction_id IS NULL' : ''}
   ORDER BY COALESCE(r.purchased_at, r.created_at) DESC LIMIT ?`).all(limit)
  .map((r) => ({ ...r, bill_data: undefined, line_items: r.line_items ? JSON.parse(r.line_items) : null }))

function attachReceipt(receiptId, transactionId) {
  const n = conn().prepare('UPDATE receipts SET transaction_id=? WHERE id=?').run(transactionId, receiptId).changes
  audit('attach_receipt', null, { receiptId, transactionId }, n)
  return getReceipt(receiptId)
}

// ---- balances / budgets / receipts ---------------------------------------

function recordBalance({ account, as_of_date, balance_cents, currency = 'USD' }) {
  const a = accountByName(account) || upsertAccount({ name: account })
  conn().prepare(`INSERT INTO balances (account_id, as_of_date, balance_cents, currency) VALUES (?,?,?,?)
                  ON CONFLICT(account_id, as_of_date) DO UPDATE SET balance_cents=excluded.balance_cents`)
    .run(a.id, as_of_date, balance_cents, currency)
  audit('record_balance', null, { account, as_of_date }, 1)
  return { account, as_of_date, balance_cents }
}
const listBalances = (account) => account
  ? conn().prepare('SELECT b.*, a.name account FROM balances b JOIN accounts a ON a.id=b.account_id WHERE a.name=? ORDER BY as_of_date DESC').all(account)
  : conn().prepare('SELECT b.*, a.name account FROM balances b JOIN accounts a ON a.id=b.account_id ORDER BY as_of_date DESC').all()

function setBudget({ category, period = 'monthly', limit_cents, currency = 'USD' }) {
  conn().prepare(`INSERT INTO budgets (category, period, limit_cents, currency) VALUES (?,?,?,?)
                  ON CONFLICT(category, period) DO UPDATE SET limit_cents=excluded.limit_cents`)
    .run(category, period, limit_cents, currency)
  audit('set_budget', null, { category, period }, 1)
  return { category, period, limit_cents }
}
const listBudgets = () => conn().prepare('SELECT * FROM budgets ORDER BY category').all()

function addReceipt(r) {
  const c = conn()
  const ext = r.external_id || crypto.createHash('sha256')
    .update([r.merchant, r.purchased_at, r.total_cents].join('|')).digest('hex').slice(0, 32)
  const before = c.prepare('SELECT id FROM receipts WHERE external_id=?').get(ext)
  c.prepare(`INSERT INTO receipts (transaction_id, merchant, purchased_at, total_cents, tax_cents,
              currency, line_items, image_path, source, external_id)
             VALUES (?,?,?,?,?,?,?,?,?,?)
             ON CONFLICT(external_id) DO UPDATE SET
               transaction_id=COALESCE(excluded.transaction_id, receipts.transaction_id),
               line_items=COALESCE(excluded.line_items, receipts.line_items),
               -- image_path must update too: the natural key is merchant|date|total, so
               -- retaking the photo for the same purchase collides here. COALESCE keeps the
               -- existing image when the caller sends none (MCP add_receipt never sends one).
               image_path=COALESCE(excluded.image_path, receipts.image_path)`)
    .run(r.transaction_id ?? null, r.merchant ?? null, r.purchased_at ?? null, r.total_cents ?? null,
         r.tax_cents ?? null, r.currency || 'USD',
         r.line_items ? JSON.stringify(r.line_items) : null, r.image_path ?? null,
         r.source || 'chatgpt', ext)
  audit('add_receipt', null, { merchant: r.merchant }, 1)
  const row = c.prepare('SELECT id FROM receipts WHERE external_id=?').get(ext)
  if (row) syncReceiptItems(row.id)
  return { id: row?.id, external_id: ext, inserted: !before }
}

// ── generated bills ───────────────────────────────────────────────────────────
const setBillStatus = (id, status, error = null) =>
  conn().prepare('UPDATE receipts SET bill_status=?, bill_error=? WHERE id=?').run(status, error, id)
const receiptsAwaitingBill = () =>
  conn().prepare("SELECT id FROM receipts WHERE bill_status IN ('pending','reading') ORDER BY id").all().map((r) => r.id)

// Store what Claude read and fill only the blanks: anything typed by hand (a split share as
// the total, a nicer merchant name) wins over the photo. Then try to attach it to a transaction.
function applyBill(id, x) {
  const c = conn()
  const r = c.prepare('SELECT * FROM receipts WHERE id=?').get(id)
  if (!r) return null
  const total = x.total == null ? null : toCents(x.total)
  const at = /^\d{4}-\d{2}-\d{2}/.test(x.purchased_at || '') ? x.purchased_at : null
  const items = (x.line_items || []).filter((l) => l && l.name).map(toStoredLine)
  // A split share ("Corner Market for a friend") is the same purchase as the full receipt —
  // itemising both would count every item twice in price history, so it keeps the bill only.
  const itemisedElsewhere = total != null && at && c.prepare(`SELECT 1 FROM receipts WHERE id<>? AND total_cents=?
    AND date(purchased_at)=date(?) AND json_array_length(COALESCE(line_items,'[]'))>0`).get(id, total, at)
  const hasItems = JSON.parse(r.line_items || '[]').length > 0
  const setItems = items.length > 0 && !hasItems && !itemisedElsewhere
  const sameTotal = r.total_cents == null || r.total_cents === total   // printed tax only fits the printed total
  c.prepare(`UPDATE receipts SET merchant=COALESCE(merchant,?), purchased_at=COALESCE(purchased_at,?),
               total_cents=COALESCE(total_cents,?), tax_cents=CASE WHEN ? THEN COALESCE(tax_cents,?) ELSE tax_cents END,
               line_items=CASE WHEN ? THEN ? ELSE line_items END,
               bill_data=?, bill_status='done', bill_error=NULL WHERE id=?`)
    .run(x.merchant || null, at, total, sameTotal ? 1 : 0, x.tax == null ? null : toCents(x.tax),
         setItems ? 1 : 0, JSON.stringify(items), JSON.stringify({ ...x, read_at: new Date().toISOString() }), id)
  if (setItems) syncReceiptItems(id)
  let attached = null
  if (!r.transaction_id) {
    const m = matchReceiptToTransaction({ total_cents: r.total_cents ?? total, purchased_at: r.purchased_at || at })
    if (m) { c.prepare('UPDATE receipts SET transaction_id=? WHERE id=?').run(m.id, id); attached = m.id }
  }
  audit('read_bill', null, { id }, 1,
    `${items.length} items${setItems ? '' : ' (bill only)'}${attached ? `, attached to tx ${attached}` : ''}`)
  return getReceipt(id)
}

// ── receipt line items / price history ────────────────────────────────────────

const UNIT_ALIASES = { lb: 'lb', lbs: 'lb', pound: 'lb', pounds: 'lb', oz: 'oz', ounce: 'oz', ounces: 'oz',
  kg: 'kg', kgs: 'kg', g: 'g', gm: 'g', gms: 'g', gram: 'g', grams: 'g', l: 'l', lt: 'l', ltr: 'l', liter: 'l',
  litre: 'l', ml: 'ml', gal: 'gal', gallon: 'gal', each: 'each', ea: 'each', ct: 'each', pc: 'each', pcs: 'each' }
// Packaging words that describe how it was sold, not what it is — dropped from item_key.
const PACK_WORDS = new Set(['bunch', 'bag', 'pack', 'pkg', 'count', 'ct', 'pc', 'pcs', 'each', 'ea', 'x'])

// Turn an extracted line into something comparable across receipts. Two jobs:
//   1. item_key — the name with weights, pack sizes and price annotations stripped, so
//      "Bananas — 3.21 lb @ $0.49/lb" and "Bananas" both key as "bananas".
//   2. unit price — from an explicit "@ $0.49/lb" annotation when present, else total/qty.
// Deliberately conservative: it strips only patterns it recognises. An unrecognised name is
// keyed as-is rather than mangled, so a wrong merge is not silently created.
function parseReceiptLine(line) {
  const rawName = String(line.name || '').trim()
  const qtyIn = Number(line.qty) > 0 ? Number(line.qty) : 1
  const total = toCents(line.price ?? line.total ?? 0)
  let name = rawName, qty = qtyIn, unit = 'each', unitPrice = null

  // "3.21 lb @ $0.49/lb" or "3.21lb @ 0.49/lb" — an explicit weight-priced line
  const m = rawName.match(/(\d+(?:\.\d+)?)\s*([a-z]+)\s*@\s*\$?\s*(\d+(?:\.\d+)?)\s*\/\s*([a-z]+)/i)
  if (m && UNIT_ALIASES[m[2].toLowerCase()]) {
    qty = Number(m[1]); unit = UNIT_ALIASES[m[2].toLowerCase()]
    unitPrice = toCents(m[3])
    name = rawName.slice(0, m.index).replace(/[\s\-—–:,(]+$/, '').trim() || rawName
  } else {
    // bare pack size in the name ("2% Milk 1 gal", "Rice 20 lb") — record the unit, keep qty
    const u = rawName.match(/\b(\d+(?:\.\d+)?)\s*(lb|lbs|oz|kg|g|gm|ml|l|gal|ct|pc|pcs)\b\.?/i)
    if (u && UNIT_ALIASES[u[2].toLowerCase()]) { unit = UNIT_ALIASES[u[2].toLowerCase()]; qty = qtyIn * Number(u[1]) }
    // ponytail: a fractional count is a weight (nobody buys 0.18 of a pepper); US receipts weigh in lb
    if (unit === 'each' && !Number.isInteger(qty)) unit = 'lb'
    if (qty > 0 && total > 0) unitPrice = Math.round(total / qty)
  }
  const item_key = name.toLowerCase()
    .replace(/\b\d+(?:\.\d+)?\s*(lb|lbs|oz|kg|g|gm|ml|l|gal|ct|pc|pcs)\b\.?/g, ' ')   // pack sizes
    .replace(/\(.*?\)/g, ' ')                                                         // parentheticals
    .replace(/[^a-z0-9%& ]+/g, ' ')                                                   // punctuation
    .split(/\s+/).filter((w) => w && !PACK_WORDS.has(w))
    // ponytail: naive singular so peppers/pepper and livers/liver share a key. "leaves"→"leave" is
    // ugly but keys are internal — the view shows the printed name. Swap in a stemmer if it misfires.
    .map((w) => w.length > 3 && /[a-z]s$/.test(w) && !/ss$/.test(w) ? w.slice(0, -1) : w)
    .join(' ') || rawName.toLowerCase()
  return { name, item_key, qty, unit, unit_price_cents: unitPrice, total_cents: total }
}

// Rebuild the derived rows for one receipt from its line_items JSON. Delete+reinsert keeps
// it idempotent — re-adding a receipt with corrected items never leaves stale lines behind.
function syncReceiptItems(receiptId) {
  const c = conn()
  const r = c.prepare('SELECT id, merchant, purchased_at, line_items FROM receipts WHERE id=?').get(receiptId)
  if (!r) return 0
  let items = []
  try { items = JSON.parse(r.line_items || '[]') } catch { items = [] }
  if (!Array.isArray(items)) items = []
  const del = c.prepare('DELETE FROM receipt_items WHERE receipt_id=?')
  const ins = c.prepare(`INSERT INTO receipt_items (receipt_id, line_no, name, item_key, qty, unit,
                          unit_price_cents, total_cents, merchant, purchased_at) VALUES (?,?,?,?,?,?,?,?,?,?)`)
  // keys this receipt already had: add_receipt re-reads old receipts, and those are not new purchases
  const had = new Set(c.prepare('SELECT item_key FROM receipt_items WHERE receipt_id=?').all(receiptId).map((x) => x.item_key))
  del.run(receiptId)
  let n = 0
  items.forEach((line, i) => {
    if (!line || !line.name) return
    const p = parseReceiptLine(line)
    ins.run(receiptId, i, p.name, p.item_key, p.qty, p.unit, p.unit_price_cents, p.total_cents,
            r.merchant ?? null, r.purchased_at ?? null)
    n++
  })
  closeBoughtFromReceipt(receiptId, had)
  return n
}

// Every distinct item with the numbers a price view needs: how often bought, the price range,
// and the last two unit prices so a trend arrow is computable without a second query.
function priceItems({ q = null, merchant = null, limit = 200 } = {}) {
  const where = ['unit_price_cents IS NOT NULL']; const args = []
  if (q) { where.push('(item_key LIKE ? OR name LIKE ?)'); args.push(`%${q.toLowerCase()}%`, `%${q}%`) }
  if (merchant) { where.push('merchant = ?'); args.push(merchant) }
  const rows = conn().prepare(`
    SELECT item_key,
           MIN(name) AS name,
           unit,
           COUNT(*) AS purchases,
           COUNT(DISTINCT merchant) AS merchants,
           MIN(unit_price_cents) AS min_cents,
           MAX(unit_price_cents) AS max_cents,
           ROUND(AVG(unit_price_cents)) AS avg_cents,
           MIN(purchased_at) AS first_at,
           MAX(purchased_at) AS last_at,
           SUM(total_cents) AS spent_cents
      FROM receipt_items
     WHERE ${where.join(' AND ')}
  GROUP BY item_key, unit
  ORDER BY purchases DESC, last_at DESC
     LIMIT ?`).all(...args, limit)
  const latest = conn().prepare(`SELECT unit_price_cents, merchant FROM receipt_items
                                  WHERE item_key=? AND unit=? AND unit_price_cents IS NOT NULL
                               ORDER BY purchased_at DESC, id DESC LIMIT 2`)
  // One display name per item_key even when it was bought in two units ("Green bell peppers"
  // by weight, "Green bell pepper" by count) — the alphabetically-first printed name wins.
  const nameOf = new Map()
  for (const r of rows) if (!nameOf.has(r.item_key) || r.name < nameOf.get(r.item_key)) nameOf.set(r.item_key, r.name)
  return rows.map((r) => {
    r = { ...r, name: nameOf.get(r.item_key) }
    const l = latest.all(r.item_key, r.unit)
    const last = l[0]?.unit_price_cents ?? null, prev = l[1]?.unit_price_cents ?? null
    return { ...r, last_cents: last, prev_cents: prev,
             change_pct: last != null && prev ? Math.round(((last - prev) / prev) * 1000) / 10 : null,
             last_merchant: l[0]?.merchant ?? null }
  })
}

// Full purchase history for one item — the series a trend chart is drawn from.
function priceHistory(item_key, { unit = null } = {}) {
  const args = [item_key]; let extra = ''
  if (unit) { extra = ' AND unit=?'; args.push(unit) }
  return conn().prepare(`
    SELECT ri.id, ri.receipt_id, ri.name, ri.qty, ri.unit, ri.unit_price_cents, ri.total_cents,
           ri.merchant, ri.purchased_at, r.transaction_id
      FROM receipt_items ri LEFT JOIN receipts r ON r.id = ri.receipt_id
     WHERE ri.item_key=?${extra}
  ORDER BY ri.purchased_at ASC, ri.id ASC`).all(...args)
}

// ── inventory ─────────────────────────────────────────────────────────────────

const localDay = () => { const n = new Date(); return `${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}-${String(n.getDate()).padStart(2, '0')}` }
// purchased_at is free text from the extractor. One that does not start YYYY-MM-DD would turn
// every estimate into NaN, so such a line is simply not a purchase.
const HAS_DAY = "purchased_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*'"

// The one definition of "a purchase": dated, product-only receipt lines, oldest first.
// inventory() and markUsedUp() both read through it so they always agree on what exists.
const purchaseLines = (c, item_key = null) => c.prepare(
  `SELECT item_key, unit, name, qty, unit_price_cents, total_cents, merchant, purchased_at
     FROM receipt_items WHERE ${HAS_DAY} AND (? IS NULL OR item_key=?) ORDER BY purchased_at, id`)
  .all(item_key, item_key).filter((r) => isProductLine(r.name, r.total_cents))

// Household items with what is left of each, rebuilt from receipt lines on every call.
// ponytail: reads every dated receipt line; fine for one household, add a cache if a year of receipts feels slow.
function inventory({ q = null, status = null, include_untracked = false, today = localDay() } = {}) {
  const c = conn(), key = (k, u) => `${k}\0${u}`
  const pairs = new Map(), used = new Map()
  for (const r of purchaseLines(c)) {
    const k = key(r.item_key, r.unit)
    if (!pairs.has(k)) pairs.set(k, { item_key: r.item_key, unit: r.unit, rows: [], ticks: [] })
    pairs.get(k).rows.push(r)
  }
  for (const e of c.prepare("SELECT item_key, unit, at FROM item_events WHERE kind='used_up'").all()) {
    const k = key(e.item_key, e.unit)
    used.set(k, [...(used.get(k) || []), e.at])
  }
  const tracked = new Map(c.prepare('SELECT item_key, unit, tracked FROM item_settings').all().map((s) => [key(s.item_key, s.unit), s.tracked]))
  const estimate = (p) => estimateItem({
    purchases: [...p.rows.map((r) => ({ date: r.purchased_at, qty: r.qty })), ...p.ticks],
    usedUp: used.get(key(p.item_key, p.unit)) || [], tracked: tracked.get(key(p.item_key, p.unit)) ?? null, today })

  // Ticked bought on the shopping list with no receipt: a rebuy of the last quantity on that day,
  // for the unit bought most recently, unless a receipt for the item already covers the day.
  const day = (r) => r.purchased_at.slice(0, 10)
  for (const t of c.prepare(`SELECT item_key, restock_date FROM shopping_list
                              WHERE status='bought' AND restock_date IS NOT NULL AND item_key IS NOT NULL ORDER BY id`).all()) {
    const mine = [...pairs.values()].filter((p) => p.item_key === t.item_key)
    if (!mine.length || mine.some((p) => p.rows.some((r) => day(r) === t.restock_date.slice(0, 10)))) continue
    const p = mine.reduce((a, b) => (day(b.rows.at(-1)) >= day(a.rows.at(-1)) ? b : a))
    p.ticks.push({ date: t.restock_date, qty: estimate(p).last_qty })
  }

  // one display name per item_key, even when it was bought in two units: the alphabetically first printed name
  const nameOf = new Map()
  for (const p of pairs.values()) for (const r of p.rows) if (!nameOf.has(r.item_key) || r.name < nameOf.get(r.item_key)) nameOf.set(r.item_key, r.name)

  const needle = q ? q.toLowerCase() : null, out = []
  for (const p of pairs.values()) {
    const name = nameOf.get(p.item_key), t = tracked.get(key(p.item_key, p.unit)) ?? null
    if (needle && !p.item_key.includes(needle) && !name.toLowerCase().includes(needle)) continue
    const e = estimate(p)
    if (!include_untracked && ['off', 'once', 'lapsed'].includes(e.status)) continue
    if (status && e.status !== status) continue
    const cheapest = p.rows.filter((r) => r.unit_price_cents != null && r.merchant && dayNum(today) - dayNum(r.purchased_at) <= 90)
      .reduce((a, r) => (!a || r.unit_price_cents <= a.unit_price_cents ? r : a), null)   // newest wins a tie
    out.push({ item_key: p.item_key, unit: p.unit, name, tracked: t == null ? 'auto' : t ? 'on' : 'off', ...e,
      last_price_cents: p.rows.findLast((r) => r.unit_price_cents != null)?.unit_price_cents ?? null,
      cheapest_merchant: cheapest?.merchant ?? null })
  }
  return out.sort((a, b) => a.name.localeCompare(b.name) || a.unit.localeCompare(b.unit))
}

// "I ran out." Closes the current cycle early, which is how the estimate gets real data.
// unit defaults to the one bought most recently; the same (item, unit, day) twice is a no-op.
function markUsedUp({ item_key, unit = null, at, actor = null }) {
  if (!/^\d{4}-\d{2}-\d{2}/.test(at || '')) throw new Error('at must be YYYY-MM-DD')
  const c = conn(), d = at.slice(0, 10)
  const hit = purchaseLines(c, item_key).findLast((r) => !unit || r.unit === unit)
  if (!hit) throw new Error(`no purchases of ${item_key}`)
  const n = c.prepare(`INSERT INTO item_events (item_key, unit, kind, at, actor)
                       SELECT ?, ?, 'used_up', ?, ?
                        WHERE NOT EXISTS (SELECT 1 FROM item_events WHERE item_key=? AND unit=? AND at=?)`)
    .run(item_key, hit.unit, d, actor, item_key, hit.unit, d).changes
  if (n) audit('mark_used_up', actor, { item_key, unit: hit.unit, at: d }, 1)
  return { item_key, unit: hit.unit, at: d }
}

// Override the 2+ purchase days rule for one item. tracked: true/1 on, false/0 off, null back to auto.
function setItemTracking({ item_key, unit, tracked, actor = null }) {
  const t = tracked == null ? null : tracked ? 1 : 0, c = conn()
  if (t == null) c.prepare('DELETE FROM item_settings WHERE item_key=? AND unit=?').run(item_key, unit)
  else c.prepare(`INSERT INTO item_settings (item_key, unit, tracked) VALUES (?,?,?)
                  ON CONFLICT(item_key, unit) DO UPDATE SET tracked=excluded.tracked`).run(item_key, unit, t)
  audit('set_item_tracking', actor, { item_key, unit, tracked: t }, 1)
  return { item_key, unit, tracked: t }
}

// ── shopping list ─────────────────────────────────────────────────────────────

const RUN_LOCK_MS = 120000   // a run that has not finished by now crashed; its lock is free again
// Closing a row notes how far receipts and Used up taps had got. "Anything new since?" is then a plain
// id comparison (isSuppressed) and never depends on clocks (a receipt can be uploaded days after the purchase).
const CLOSE_STAMP = `closed_at=datetime('now'), updated_at=datetime('now'),
  close_event_id=(SELECT COALESCE(MAX(id),0) FROM item_events),
  close_receipt_id=(SELECT COALESCE(MAX(id),0) FROM receipts)`
const keyOf = (name) => parseReceiptLine({ name }).item_key   // the same normaliser receipt lines go through
const ids = (a) => (Array.isArray(a) ? a : []).map(Number).filter(Number.isInteger)

// Close open rows by id, optionally only those matching `only` (a source test). Returns how many closed.
function closeRows(list, status, only = '1', restock = null) {
  const q = conn().prepare(`UPDATE shopping_list SET status=?, restock_date=?, ${CLOSE_STAMP}
                             WHERE id=? AND status='open' AND ${only}`)
  return list.reduce((n, id) => n + q.run(status, restock, id).changes, 0)
}

// True while something closed the item and nothing has happened to it since: no Used up tap and no
// receipt line newer than the close. A row closed any earlier can only be older, so any one match is enough.
function isSuppressed(item_key) {
  return !!conn().prepare(`SELECT 1 FROM shopping_list s WHERE s.item_key=? AND s.status<>'open'
      AND NOT EXISTS (SELECT 1 FROM item_events e WHERE e.item_key=s.item_key AND e.id > s.close_event_id)
      AND NOT EXISTS (SELECT 1 FROM receipt_items r WHERE r.item_key=s.item_key AND r.receipt_id > s.close_receipt_id)
      LIMIT 1`).get(item_key)
}

// The open list, each row with the price hint of the matching inventory item, and the AI run status.
function shoppingList({ today = localDay() } = {}) {
  const inv = inventory({ today, include_untracked: true })
  const items = conn().prepare("SELECT id, item_key, unit, name, qty, source, reason FROM shopping_list WHERE status='open' ORDER BY id")
    .all().map((r) => {
      // same unit when the row has one, else any unit bought under that key
      const hit = inv.find((i) => i.item_key === r.item_key && i.unit === r.unit) || inv.find((i) => i.item_key === r.item_key)
      return { ...r, last_price_cents: hit?.last_price_cents ?? null, cheapest_merchant: hit?.cheapest_merchant ?? null }
    })
  const total_cents = items.reduce((t, r) => t + (r.last_price_cents == null ? 0 : Math.round((r.qty ?? 1) * r.last_price_cents)), 0)
  const s = shoppingState()
  return { items, total_cents, ai: { last_run_at: s.last_run_at, ok: s.last_ok == null ? null : !!s.last_ok, message: s.last_message,
    pending: !!s.requested_at || (!!s.running_since && Date.now() - Date.parse(s.running_since) < RUN_LOCK_MS) } }
}

// Put every tracked item that is used up or about to run out on the list, unless it is already there
// or was closed with nothing new since.
function refreshShoppingRules({ today = localDay() } = {}) {
  const c = conn(), open = new Set(c.prepare("SELECT item_key FROM shopping_list WHERE status='open'").all().map((r) => r.item_key))
  const ins = c.prepare("INSERT INTO shopping_list (item_key, unit, name, qty, source, reason) VALUES (?,?,?,?,'rule',?)")
  let added = 0
  for (const s of ruleSuggestions(inventory({ today }))) {
    if (open.has(s.item_key) || isSuppressed(s.item_key)) continue
    ins.run(s.item_key, s.unit, s.name, s.qty, s.reason); open.add(s.item_key); added++
  }
  if (added) audit('refresh_shopping_rules', null, { today }, added)
  return { added }
}

// The owner's edits. bought = ticked at the shop; dismiss = decline a suggestion; remove = delete their own item.
// A typed name merges into an open row for the same item (their row wins) instead of listing it twice.
function updateShoppingList({ add = [], bought = [], dismiss = [], remove = [], actor = null, today = localDay() } = {}) {
  const c = conn(); let added = 0, changed = 0
  for (const a of Array.isArray(add) ? add : []) {
    const name = clip(a?.name, NAME_MAX); if (!name) continue
    const key = keyOf(name), qty = cleanQty(a.qty)
    const row = c.prepare("SELECT id FROM shopping_list WHERE item_key=? AND status='open' ORDER BY id LIMIT 1").get(key)
    if (row) {
      c.prepare("UPDATE shopping_list SET source='user', name=?, qty=COALESCE(?, qty), updated_at=datetime('now') WHERE id=?").run(name, qty, row.id)
      changed++
    } else {
      c.prepare("INSERT INTO shopping_list (item_key, unit, name, qty, source) VALUES (?,NULL,?,?,'user')").run(key, name, qty)
      added++
    }
  }
  // a tick with no receipt is a restock today: inventory() counts it as a rebuy of the last quantity
  changed += closeRows(ids(bought), 'bought', '1', String(today).slice(0, 10))
  changed += closeRows(ids(dismiss), 'dismissed', "source<>'user'")
  changed += closeRows(ids(remove), 'removed', "source='user'")
  audit('update_shopping_list', actor, { add, bought, dismiss, remove }, added + changed)
  return { added, changed }
}

// A receipt that has an open item's key bought it. Only keys the receipt did not already have count (`had`):
// add_receipt re-reads old receipts, and one of those must not tick off something added to the list since.
function closeBoughtFromReceipt(receiptId, had = new Set()) {
  const keys = conn().prepare('SELECT item_key, name, total_cents FROM receipt_items WHERE receipt_id=?').all(receiptId)
    .filter((r) => !had.has(r.item_key) && isProductLine(r.name, r.total_cents)).map((r) => r.item_key)
  if (!keys.length) return 0
  const n = conn().prepare(`UPDATE shopping_list SET status='bought', ${CLOSE_STAMP}
                             WHERE status='open' AND item_key IN (${keys.map(() => '?').join(',')})`).run(...keys).changes
  if (n) audit('close_shopping_bought', null, { receiptId }, n)
  return n
}

// What the AI proposed, applied with care: its output is untrusted text. It never touches the owner's
// rows, never re-adds something closed with nothing new since, and bad entries are counted, not written.
function applyShoppingAI({ add, update, remove } = {}, { actor = 'claude' } = {}) {
  const c = conn(), list = (x) => (Array.isArray(x) ? x : [])
  const n = { added: 0, updated: 0, removed: 0, refused: 0 }
  const adds = list(add)
  n.refused += Math.max(0, adds.length - MAX_AI_ADDS)   // the rest of an over-long list
  for (const a of adds.slice(0, MAX_AI_ADDS)) {
    const name = clip(a?.name, NAME_MAX), given = typeof a?.item_key === 'string' ? clip(a.item_key.toLowerCase(), NAME_MAX) : ''
    const key = given || (name && keyOf(name))
    if (!name || c.prepare("SELECT 1 FROM shopping_list WHERE item_key=? AND status='open'").get(key) || isSuppressed(key)) { n.refused++; continue }
    c.prepare("INSERT INTO shopping_list (item_key, unit, name, qty, source, reason) VALUES (?,?,?,?,'ai',?)")
      .run(key, clip(a.unit, 20) || null, name, cleanQty(a.qty), clip(a.reason, REASON_MAX) || null)
    n.added++
  }
  for (const u of list(update)) {   // a bad qty or empty reason keeps what is there
    const id = Number(u?.id)
    const done = Number.isInteger(id) && c.prepare(`UPDATE shopping_list SET qty=COALESCE(?, qty), reason=COALESCE(?, reason), updated_at=datetime('now')
                                                     WHERE id=? AND status='open' AND source<>'user'`)
      .run(cleanQty(u.qty), clip(u.reason, REASON_MAX) || null, id).changes
    done ? n.updated++ : n.refused++
  }
  for (const r of list(remove)) {
    const id = Number(r?.id)
    Number.isInteger(id) && closeRows([id], 'removed', "source<>'user'") ? n.removed++ : n.refused++
  }
  audit('apply_shopping_ai', actor, { add, update, remove }, n.added + n.updated + n.removed, `${n.refused} refused`)
  return n
}

// ── AI run bookkeeping (one row, shared by the web process that calls Claude and everyone who asks) ──
const shoppingState = () => conn().prepare('SELECT * FROM shopping_state WHERE id=1').get()

// Only sets a flag: the ledger-web timer does the work, so callers never wait on Claude.
function requestShoppingRefresh() {
  conn().prepare('UPDATE shopping_state SET requested_at=? WHERE id=1').run(new Date().toISOString())
  audit('refresh_shopping_list', null, {}, 1)
  return { queued: true }
}

// One run at a time. Claiming clears the request, so one arriving mid-run is kept for the next tick.
// A single UPDATE decides it, which keeps two processes from both winning.
function claimShoppingRun(now = new Date()) {
  return conn().prepare(`UPDATE shopping_state SET running_since=?, requested_at=NULL
                          WHERE id=1 AND (running_since IS NULL OR running_since <= ?)`)
    .run(now.toISOString(), new Date(now - RUN_LOCK_MS).toISOString()).changes === 1
}

// marker: shoppingChangeMarker() as read BEFORE the run, so data that changed meanwhile triggers another.
function finishShoppingRun({ ok, message = null, marker = null }) {
  conn().prepare('UPDATE shopping_state SET last_run_at=?, last_ok=?, last_message=?, last_marker=?, running_since=NULL WHERE id=1')
    .run(new Date().toISOString(), ok ? 1 : 0, message, marker)
}

// Changes whenever a receipt line or a Used up tap does. receipt_items is rebuilt by delete+insert,
// so the count is in it too: a re-read that removes the newest row would not move the max id.
function shoppingChangeMarker() {
  const q = (t) => conn().prepare(`SELECT COALESCE(MAX(id),0) m, COUNT(*) n FROM ${t}`).get()
  const a = q('receipt_items'), b = q('item_events')
  return `${a.m}:${a.n}:${b.m}:${b.n}`
}

// Replace a receipt's line items (and optionally tax) after reading its photo. Keeps the JSON
// column authoritative and re-derives receipt_items from it.
function setReceiptItems(id, line_items, { tax_cents = undefined } = {}) {
  const c = conn()
  if (!c.prepare('SELECT id FROM receipts WHERE id=?').get(id)) return null
  c.prepare('UPDATE receipts SET line_items=?, tax_cents=COALESCE(?, tax_cents) WHERE id=?')
    .run(JSON.stringify(line_items), tax_cents ?? null, id)
  const n = syncReceiptItems(id)
  audit('set_receipt_items', null, { id, n }, 1)
  return n
}

// Match a receipt to a transaction: same-ish day, amount within tolerance. Deliberately
// conservative — a wrong auto-match silently attaches a receipt to unrelated spending.
function matchReceiptToTransaction({ total_cents, purchased_at, day_window = 3, pct_tolerance = 0.02 }) {
  if (total_cents == null || !purchased_at) return null
  const day = purchased_at.slice(0, 10)
  const lo = Math.round(total_cents * (1 - pct_tolerance))
  const hi = Math.round(total_cents * (1 + pct_tolerance))
  return conn().prepare(
    `SELECT t.*, a.name account FROM transactions t JOIN accounts a ON a.id=t.account_id
     WHERE t.voided_at IS NULL AND t.direction='expense'
       AND t.amount_cents BETWEEN ? AND ?
       AND date(t.posted_at) BETWEEN date(?, ?) AND date(?, ?)
     ORDER BY ABS(t.amount_cents - ?) LIMIT 1`)
    .get(lo, hi, day, `-${day_window} days`, day, `+${day_window} days`, total_cents) || null
}

// ---- audit ---------------------------------------------------------------

function audit(tool, actor, args, affected, detail = null) {
  try {
    const hash = crypto.createHash('sha256').update(JSON.stringify(args ?? {})).digest('hex').slice(0, 16)
    conn().prepare('INSERT INTO audit_log (tool, actor, args_hash, affected, detail) VALUES (?,?,?,?,?)')
      .run(tool, actor, hash, affected ?? null, detail)
  } catch { /* audit must never break the write it is recording */ }
}
const listAudit = (limit = 50) => conn().prepare('SELECT * FROM audit_log ORDER BY id DESC LIMIT ?').all(limit)

const stats = () => ({
  transactions: conn().prepare('SELECT COUNT(*) n FROM transactions WHERE voided_at IS NULL').get().n,
  accounts: conn().prepare('SELECT COUNT(*) n FROM accounts').get().n,
  receipts: conn().prepare('SELECT COUNT(*) n FROM receipts').get().n,
  range: conn().prepare('SELECT MIN(posted_at) first, MAX(posted_at) last FROM transactions WHERE voided_at IS NULL').get(),
})

module.exports = {
  initDb, toCents, externalId, receiptDir, receiptImageFile,
  upsertAccount, listAccounts, accountByName,
  upsertTransaction, upsertTransactions, listTransactions, countTransactions, searchTransactions,
  summary, categoryBreakdown, setCategory, markReviewed, voidTransaction,
  updateTransaction, getTransaction, receiptsForTransaction,
  monthlySeries, distinctCategories, categoryStats, renameCategory, listReceipts, attachReceipt,
  recordBalance, listBalances, setBudget, listBudgets,
  addReceipt, matchReceiptToTransaction, setBillStatus, receiptsAwaitingBill, applyBill,
  parseReceiptLine, syncReceiptItems, setReceiptItems, priceItems, priceHistory,
  inventory, markUsedUp, setItemTracking,
  shoppingList, refreshShoppingRules, isSuppressed, updateShoppingList, closeBoughtFromReceipt, applyShoppingAI,
  requestShoppingRefresh, shoppingState, claimShoppingRun, finishShoppingRun, shoppingChangeMarker,
  audit, listAudit, stats,
}

// Receipt + its attached transaction (added for the MCP get_receipt tool).
function getReceipt(id) {
  const r = conn().prepare('SELECT * FROM receipts WHERE id = ?').get(id)
  if (!r) return null
  const tx = r.transaction_id
    ? conn().prepare('SELECT t.*, a.name account FROM transactions t JOIN accounts a ON a.id=t.account_id WHERE t.id=?').get(r.transaction_id)
    : null
  return { ...r, line_items: r.line_items ? JSON.parse(r.line_items) : null,
           bill_data: r.bill_data ? JSON.parse(r.bill_data) : null, transaction: tx }
}
module.exports.getReceipt = getReceipt
