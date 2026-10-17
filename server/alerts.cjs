// Parse a Bank of America alert (email body or SMS text) into a transaction.
// Formats seen in real alerts:
//   "…Visa ending in 1234 Amount: $12.34 Date: October 1, 2026 Where: Example Shop This may…"
//   "We've credited your account … ending in 1234 Amount: $9.44 Date of credit: September 30, 2026 Merchant: APPLE.COM/BILL …"
//   "We received your credit card payment … ending in 1234 Payment amount $500.00 Date posted September 25, 2026"
// SMS wording varies, so each field also has a looser fallback ("…1234", "at X on 10/01").
// Returns { ok:true, last4, amount_cents, direction, merchant, date } or { ok:false, kind, error }.

const MONTHS = ['january','february','march','april','may','june','july','august','september','october','november','december']

function parseDate(text, today) {
  let m = text.match(/\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2}),\s*(\d{4})/i)
  if (m) return `${m[3]}-${String(MONTHS.indexOf(m[1].toLowerCase()) + 1).padStart(2, '0')}-${m[2].padStart(2, '0')}`
  m = text.match(/\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/)
  if (m) {
    const y = m[3] ? (m[3].length === 2 ? '20' + m[3] : m[3]) : today.slice(0, 4)
    return `${y}-${m[1].padStart(2, '0')}-${m[2].padStart(2, '0')}`
  }
  return today
}

function parseBofaAlert(raw, today = new Date().toISOString().slice(0, 10)) {
  const text = String(raw || '').replace(/&#39;/g, "'").replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim()
  if (!text) return { ok: false, kind: 'empty', error: 'no alert text' }
  if (/payment (amount|received)|received your (credit card )?payment|thank you for your payment/i.test(text))
    return { ok: false, kind: 'payment', error: 'card payment, not a charge — record it from the bank side' }
  if (/statement is available|credit limit|balance transfer|promotional/i.test(text))
    return { ok: false, kind: 'not_a_transaction', error: 'not a transaction alert' }

  const last4 = (text.match(/ending in (\d{4})/i) || text.match(/(?:\.{2,3}|\bx|\*)(\d{4})\b/i) || [])[1]
  const amt = text.match(/Amount:?\s*\$\s?([\d,]+\.\d{2})/i) || text.match(/\$\s?([\d,]+\.\d{2})/)
  if (!last4) return { ok: false, kind: 'unparsed', error: 'no card number (ending in ####) found' }
  if (!amt) return { ok: false, kind: 'unparsed', error: 'no $ amount found' }
  const amount_cents = Math.round(Number(amt[1].replace(/,/g, '')) * 100)

  const merchant = ((text.match(/(?:Where|Merchant):\s*(.+?)(?=\s+(?:This may|View|Location:|If you|Date|We |To |Amount)|$)/i)
    || text.match(/\bat\s+(.+?)(?=\s+on\s+\d|\s+for\s+\$|\.\s|$)/i) || [])[1] || '').trim().slice(0, 120) || null

  // Ride apps pre-authorise ("LYFT TEMP AUTH HOLD", "UBR PENDING.UBER.COM") and later post the real,
  // different amount — logging the hold would double-count the ride.
  if (merchant && /temp auth hold|\bpending\./i.test(merchant)) return { ok: false, kind: 'hold', error: `pre-authorisation hold (${merchant}), the final charge comes separately` }
  const direction = /credited your account|\bcredit of\b|refund|date of credit/i.test(text) ? 'income' : 'expense'
  return { ok: true, last4, amount_cents, direction, merchant, date: parseDate(text, today) }
}


// One alert in, at most one row out. Rows land with source 'bofa-alert', so they sit in the
// Review queue until confirmed, and the category is only copied from the last row with the
// same merchant (never guessed by rule — see categorize.cjs on why).
const merchantKey = (m, n = 5) => String(m || '').toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, n)
const addDays = (d, n) => { const t = new Date(d + 'T12:00:00Z'); t.setUTCDate(t.getUTCDate() + n); return t.toISOString().slice(0, 10) }
// `at` is the alert's own time (HH:MM:SS) when known — an email's timestamp; defaults to now.
function ingestAlert({ db, text, today = new Date().toISOString().slice(0, 10), at = null, actor = null, source = 'bofa-alert' }) {
  const a = parseBofaAlert(text, today)
  if (!a.ok) return a
  const acct = db.listAccounts().find((x) => !/merged/i.test(x.name) && new RegExp(`\\b${a.last4}\\b`).test(x.name))
  if (!acct) return { ok: false, kind: 'unknown_card', error: `no ledger account ends in ${a.last4}` }
  // The same charge can arrive twice (text + email, or a later statement import). Same card,
  // direction and amount within 2 days with a matching merchant = already recorded.
  const near = db.listTransactions({ account: acct.name, direction: a.direction, from: addDays(a.date, -2), to: addDays(a.date, 3), limit: 500 })
  const dup = near.find((t) => t.amount_cents === a.amount_cents && (!t.merchant || !a.merchant || merchantKey(t.merchant) === merchantKey(a.merchant)))
  if (dup) return { ok: true, duplicate: true, id: dup.id, message: `Already in ledger: $${(a.amount_cents / 100).toFixed(2)} ${dup.merchant || ''}`.trim() }
  const prev = a.merchant ? db.searchTransactions(a.merchant.split(/\s+/)[0], 50).find((t) => t.category && t.direction === a.direction && merchantKey(t.merchant, 8) === merchantKey(a.merchant, 8)) : null
  const category = a.direction === 'income' ? 'Refund' : (prev?.category || null)
  const n = new Date(), p2 = (x) => String(x).padStart(2, '0')
  const r = db.upsertTransactions([{
    account: acct.name, posted_at: `${a.date}T${at || `${p2(n.getHours())}:${p2(n.getMinutes())}:${p2(n.getSeconds())}`}`,
    direction: a.direction, amount_cents: a.amount_cents, merchant: a.merchant, category,
    note: `BofA alert: ${String(text).replace(/\s+/g, ' ').trim().slice(0, 300)}`, confidence: 0.9,
  }], { source, actor })
  if (r.errors.length) return { ok: false, kind: 'write_failed', error: r.errors[0].error }
  return { ok: true, id: r.ids[0], account: acct.name, ...a, category,
    message: `Logged $${(a.amount_cents / 100).toFixed(2)} ${a.direction === 'income' ? 'refund from' : 'at'} ${a.merchant || 'unknown merchant'} on ${acct.name}${category ? ` (${category})` : ''}` }
}

module.exports = { parseBofaAlert, ingestAlert }
