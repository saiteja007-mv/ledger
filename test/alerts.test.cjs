const test = require('node:test')
const assert = require('node:assert/strict')
const { parseBofaAlert } = require('../server/alerts.cjs')
const T = '2026-10-01'

test('card-not-present charge (email wording)', () => {
  const r = parseBofaAlert('Credit card not present during this transaction Example Visa ending in 1234 Amount: $12.34 Date: October 1, 2026 Where: Example Shop This may have occurred for a', T)
  assert.deepEqual(r, { ok: true, last4: '1234', amount_cents: 1234, direction: 'expense', merchant: 'Example Shop', date: '2026-10-01' })
})

test('outside-US charge keeps merchant, drops location', () => {
  const r = parseBofaAlert('Credit card transaction outside the 50 US states … ending in 1234 Amount: $55.00 Date: September 19, 2026 Where: EXAMPLE.COM Location: France View details', T)
  assert.equal(r.merchant, 'EXAMPLE.COM'); assert.equal(r.amount_cents, 5500); assert.equal(r.date, '2026-09-19')
})

test('credit is a refund (income)', () => {
  const r = parseBofaAlert("We&#39;ve credited your account Example Visa ending in 1234 Amount: $9.44 Date of credit: September 30, 2026 Merchant: APPLE.COM/BILL 866-712-7753 CA View account activity", T)
  assert.equal(r.direction, 'income'); assert.equal(r.amount_cents, 944); assert.equal(r.merchant, 'APPLE.COM/BILL 866-712-7753 CA'); assert.equal(r.last4, '1234')
})

test('payments and statements are not charges', () => {
  assert.equal(parseBofaAlert('We received your credit card payment Thank you for your payment on this account: … ending in 1234 Payment amount $500.00', T).kind, 'payment')
  assert.equal(parseBofaAlert('Your credit card statement is available Account … - 1234 Statement Date September 23, 2026', T).kind, 'not_a_transaction')
})

test('SMS-style wording falls back to "…1234", "at X on MM/DD"', () => {
  const r = parseBofaAlert('BofA: Credit card ...1234: $11.98 purchase at CORNER MARKET #123 on 09/29. Not you? Call 800-...', T)
  assert.equal(r.last4, '1234'); assert.equal(r.amount_cents, 1198); assert.equal(r.merchant, 'CORNER MARKET #123'); assert.equal(r.date, '2026-09-29')
})

test('missing card number is reported, not guessed', () => {
  assert.equal(parseBofaAlert('A $5.00 charge was made', T).kind, 'unparsed')
})

test('ride-app pre-authorisation holds are skipped', () => {
  assert.equal(parseBofaAlert('ending in 1234 Amount: $11.93 Date: September 10, 2026 Where: LYFT TEMP AUTH HOLD This may', T).kind, 'hold')
  assert.equal(parseBofaAlert('ending in 1234 Amount: $7.77 Date: September 11, 2026 Where: UBR PENDING.UBER.COM This may', T).kind, 'hold')
  assert.equal(parseBofaAlert('ending in 1234 Amount: $5.00 Date: September 13, 2026 Where: LYFT STANDARD 09-12 This may', T).ok, true)
})
