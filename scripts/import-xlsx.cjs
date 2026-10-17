#!/usr/bin/env node
// Import a Money-Manager-style xlsx export into finance-mcp.
//
// Handles the six quirks found in the real export (738 rows, 2025-08-11 -> 2026-08-06):
//   1. TWO columns are both named "Accounts" (B and K). K duplicates the amount. We read
//      POSITIONALLY (B = account, I = amount) — a header-keyed reader silently reads
//      amounts as account names, which is exactly what happened on first parse.
//   2. Amounts carry float noise (79.34999999999999) -> integer cents.
//   3. Dates are Excel serials with real times of day (445 distinct) -> keep the time,
//      because it is what disambiguates same-day repeats.
//   4. "Description" is empty on every row; "Note"/"Subcategory" hold what signal exists.
//   5. Categories carry emoji prefixes ("🚖 Transport") -> keep display, add a normalized key.
//   6. Income/Expense also encodes Transfer-In / Transfer-Out (8 matched pairs).
//
// Usage: node scripts/import-xlsx.cjs <file.xlsx> [--dry-run]
const fs = require('node:fs')
const path = require('node:path')
const zlib = require('node:zlib')
const db = require('../server/db.cjs')

// --- minimal xlsx reader (no openpyxl/exceljs dependency) -------------------
function readXlsx(file) {
  const buf = fs.readFileSync(file)
  const files = {}
  // Walk the zip central directory.
  let eocd = buf.length - 22
  while (eocd >= 0 && buf.readUInt32LE(eocd) !== 0x06054b50) eocd--
  if (eocd < 0) throw new Error('not a zip/xlsx file')
  let off = buf.readUInt32LE(eocd + 16)
  const count = buf.readUInt16LE(eocd + 10)
  for (let i = 0; i < count; i++) {
    const nameLen = buf.readUInt16LE(off + 28)
    const extraLen = buf.readUInt16LE(off + 30)
    const commentLen = buf.readUInt16LE(off + 32)
    const localOff = buf.readUInt32LE(off + 42)
    const name = buf.toString('utf8', off + 46, off + 46 + nameLen)
    const lNameLen = buf.readUInt16LE(localOff + 26)
    const lExtraLen = buf.readUInt16LE(localOff + 28)
    const dataStart = localOff + 30 + lNameLen + lExtraLen
    const method = buf.readUInt16LE(localOff + 8)
    const compSize = buf.readUInt32LE(off + 20)
    const raw = buf.subarray(dataStart, dataStart + compSize)
    files[name] = method === 0 ? raw : zlib.inflateRawSync(raw)
    off += 46 + nameLen + extraLen + commentLen
  }
  const strings = []
  if (files['xl/sharedStrings.xml']) {
    const xml = files['xl/sharedStrings.xml'].toString('utf8')
    for (const si of xml.split('<si>').slice(1)) {
      const texts = [...si.matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((m) => decode(m[1]))
      strings.push(texts.join(''))
    }
  }
  const sheetName = Object.keys(files).find((n) => /^xl\/worksheets\/sheet1\.xml$/.test(n))
  const sheet = files[sheetName].toString('utf8')
  const rows = []
  for (const rowXml of sheet.split('<row ').slice(1)) {
    const cells = {}
    for (const m of rowXml.matchAll(/<c r="([A-Z]+)\d+"([^>]*)>([\s\S]*?)<\/c>/g)) {
      const col = m[1], attrs = m[2]
      const vm = /<v>([\s\S]*?)<\/v>/.exec(m[3])
      if (!vm) continue
      cells[col] = /t="s"/.test(attrs) ? strings[Number(vm[1])] : vm[1]
    }
    if (Object.keys(cells).length) rows.push(cells)
  }
  return rows
}
const decode = (s) => s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"').replace(/&apos;/g, "'")

// Excel serial -> local ISO datetime. Epoch is 1899-12-30 (the 1900 leap-year bug).
function excelToIso(serial) {
  const n = Number(serial)
  if (!Number.isFinite(n)) return null
  const ms = Math.round((n - 25569) * 86400 * 1000)
  const d = new Date(ms)
  const p = (x) => String(x).padStart(2, '0')
  return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())}T` +
         `${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}`
}

const DIRECTION = {
  'Exp.': 'expense', 'Expense': 'expense',
  'Income': 'income',
  'Transfer-In': 'transfer_in', 'Transfer-Out': 'transfer_out',
}

// "🚖 Transport" -> "transport". Keeps grouping stable if the emoji ever changes.
const normCategory = (c) => (c || '').replace(/[^\p{L}\p{N} &/-]/gu, '').trim().toLowerCase() || null

function main() {
  const file = process.argv[2]
  const dry = process.argv.includes('--dry-run')
  if (!file) { console.error('usage: import-xlsx.cjs <file.xlsx> [--dry-run]'); process.exit(2) }

  const rows = readXlsx(file)
  const header = rows[0]
  const data = rows.slice(1)
  console.log(`file: ${path.basename(file)}`)
  console.log(`header: ${['A','B','C','D','E','F','G','H','I','J','K'].map((c) => `${c}=${header[c] ?? ''}`).join(' ')}`)
  console.log(`rows: ${data.length}`)

  const items = []
  const skipped = []
  for (const [i, r] of data.entries()) {
    const posted_at = excelToIso(r.A)
    const account = (r.B || '').trim()
    const direction = DIRECTION[(r.G || '').trim()]
    const cents = db.toCents(r.I)
    if (!posted_at || !account || !direction || cents == null) {
      skipped.push({ row: i + 2, reason: !posted_at ? 'bad date' : !account ? 'no account' : !direction ? `unknown type '${r.G}'` : 'bad amount' })
      continue
    }
    const category = (r.C || '').trim() || null
    items.push({
      account, posted_at, direction,
      amount_cents: cents,
      currency: (r.J || 'USD').trim() || 'USD',
      base_currency: 'USD',
      fx_rate: 1.0,
      category,
      subcategory: (r.D || '').trim() || null,
      note: (r.E || '').trim() || null,
      // Column C on a transfer row holds the OTHER account, not a category.
      counter_account: direction.startsWith('transfer') ? ((r.C || '').trim() || null) : null,
      source: 'import',
      reviewed: 1,           // hand-recorded in another app; trusted, unlike LLM-sourced rows
      _norm_category: normCategory(category),
    })
  }

  console.log(`parsed: ${items.length}  skipped: ${skipped.length}`)
  if (skipped.length) console.log('  ' + JSON.stringify(skipped.slice(0, 10)))

  const byDir = {}
  for (const it of items) {
    byDir[it.direction] = byDir[it.direction] || { n: 0, cents: 0 }
    byDir[it.direction].n++; byDir[it.direction].cents += it.amount_cents
  }
  console.log('by direction:')
  for (const [k, v] of Object.entries(byDir)) console.log(`  ${k.padEnd(13)} ${String(v.n).padStart(4)}  $${(v.cents / 100).toFixed(2)}`)

  // Collisions on the natural key BEFORE writing — this is the number that tells you
  // whether the key is right. Same-day repeats must NOT collide.
  const keys = new Map()
  for (const it of items) {
    const k = db.externalId({ account: it.account, posted_at: it.posted_at, amount_cents: it.amount_cents, currency: it.currency, direction: it.direction })
    keys.set(k, (keys.get(k) || 0) + 1)
  }
  const collisions = [...keys.values()].filter((v) => v > 1).length
  console.log(`natural-key collisions: ${collisions} (rows that would merge)`)

  if (dry) { console.log('\n--dry-run: nothing written'); return }

  db.initDb()
  for (const it of items) delete it._norm_category
  const res = db.upsertTransactions(items, { source: 'import', actor: 'import-xlsx' })
  console.log(`\nwrote: inserted=${res.inserted} updated=${res.updated} errors=${res.errors.length}`)
  if (res.errors.length) console.log('  ' + JSON.stringify(res.errors.slice(0, 5)))
  console.log('stats:', JSON.stringify(db.stats()))
}

main()
