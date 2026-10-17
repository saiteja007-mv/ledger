const { test } = require('node:test')
const assert = require('node:assert')
const fx = require('../server/fx.cjs')

test('fillRates sets a USD-per-unit rate on non-USD rows only, by date', async () => {
  const seen = []
  const real = global.fetch
  global.fetch = async (url) => { seen.push(url); return { ok: true, status: 200, json: async () => ({ rates: { INR: url.includes('2024-01-05') ? 80 : 100 } }) } }
  try {
    const db = { accountByName: (n) => ({ currency: n === 'INR Savings' ? 'INR' : 'USD' }) }
    const rows = [
      { account: 'INR Savings', posted_at: '2024-01-05T12:00:00' },
      { account: 'INR Savings', posted_at: '2024-01-05T13:00:00' },            // cached, no second fetch
      { account: 'US Checking', posted_at: '2024-01-05T12:00:00' },              // USD: untouched
      { account: 'INR Savings', posted_at: '2024-01-05T12:00:00', fx_rate: 0.5 }, // explicit rate wins
    ]
    await fx.fillRates(rows, db)
    assert.deepEqual(rows.map((r) => r.fx_rate), [1 / 80, 1 / 80, undefined, 0.5])
    assert.equal(seen.length, 1)
    assert.match(seen[0], /\/2024-01-05\?from=USD&to=INR$/)
  } finally { global.fetch = real }
})
