#!/usr/bin/env node
// Poll Gmail (through Unipile's connected Google account) for Bank of America alert emails
// and log each one into the ledger with the same ingestAlert() the web endpoint uses.
//
//   node scripts/bofa-mail-poll.cjs            process alerts not seen before
//   node scripts/bofa-mail-poll.cjs --init     mark everything currently in the inbox as seen
//   node scripts/bofa-mail-poll.cjs --dry-run  parse only, write nothing
//
// Env: UNIPILE_API_BASE, UNIPILE_API_KEY, BOFA_MAIL_ACCOUNT_ID (Unipile account id).
// State: .data/bofa-mail-state.json — ids already handled, so a re-run never double-logs
// (and ingestAlert's own duplicate check covers an alert that also came in another way).
const fs = require('node:fs')
const path = require('node:path')
const db = require('../server/db.cjs')
const { parseBofaAlert, ingestAlert } = require('../server/alerts.cjs')

const SENDER = 'onlinebanking@ealerts.bankofamerica.com'
const STATE = path.join(__dirname, '..', '.data', 'bofa-mail-state.json')
const { UNIPILE_API_BASE: BASE, UNIPILE_API_KEY: KEY, BOFA_MAIL_ACCOUNT_ID: ACCOUNT } = process.env
const DRY = process.argv.includes('--dry-run'), INIT = process.argv.includes('--init')
if (!BASE || !KEY || !ACCOUNT) { console.error('need UNIPILE_API_BASE, UNIPILE_API_KEY, BOFA_MAIL_ACCOUNT_ID'); process.exit(2) }

const get = async (p) => {
  const r = await fetch(`${BASE.replace(/\/$/, '')}${p}`, { headers: { 'X-API-KEY': KEY, accept: 'application/json' }, signal: AbortSignal.timeout(30_000) })
  if (!r.ok) throw new Error(`unipile ${r.status} on ${p.split('?')[0]}`)
  return r.json()
}
// The alert sentence sits in a 50 KB HTML email full of footer links ("credit limit",
// "payment"…) that would trip the not-a-charge filters, so only a window around
// "ending in ####" is passed on, prefixed by the subject.
function alertText(e) {
  const body = (e.body_plain || String(e.body || '').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' '))
    .replace(/&nbsp;/g, ' ').replace(/&#39;/g, "'").replace(/&amp;/g, '&').replace(/\s+/g, ' ')
  const i = body.search(/ending in \d{4}/i)
  return `${e.subject || ''} ${i < 0 ? body.slice(0, 600) : body.slice(Math.max(0, i - 150), i + 350)}`
}
const local = (iso) => { const d = new Date(iso), p2 = (x) => String(x).padStart(2, '0')
  return { day: `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}`, at: `${p2(d.getHours())}:${p2(d.getMinutes())}:${p2(d.getSeconds())}` } }

;(async () => {
  let state = { seen: [] }
  try { state = JSON.parse(fs.readFileSync(STATE, 'utf8')) } catch {}
  const seen = new Set(state.seen)
  const list = await get(`/emails?account_id=${ACCOUNT}&limit=25&from=${encodeURIComponent(SENDER)}`)
  const fresh = (list.items || []).filter((e) => !seen.has(e.id)).sort((a, b) => Date.parse(a.date) - Date.parse(b.date))
  for (const item of fresh) {
    if (INIT) { seen.add(item.id); continue }
    const e = await get(`/emails/${item.id}?account_id=${ACCOUNT}`)
    const text = alertText(e), { day, at } = local(e.date)
    const r = DRY ? parseBofaAlert(text, day) : ingestAlert({ db, text, today: day, at, actor: 'gmail-poll' })
    console.log(`[bofa-mail] ${e.date} ${r.ok ? (r.duplicate ? 'duplicate' : DRY ? 'parsed' : 'logged') : r.kind}: ${r.message || r.error || JSON.stringify(r)}`)
    if (!DRY) seen.add(item.id)
  }
  if (!DRY) fs.writeFileSync(STATE, JSON.stringify({ seen: [...seen].slice(-500), updated: new Date().toISOString() }), { mode: 0o600 })
  if (INIT) console.log(`[bofa-mail] init: marked ${fresh.length} existing alert(s) as seen`)
  else if (!fresh.length) console.log('[bofa-mail] no new alerts')
})().catch((e) => { console.error('[bofa-mail]', e.message); process.exit(1) })
