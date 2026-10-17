// fx.cjs — live exchange rates, so non-USD rows convert to the USD base without anyone typing
// a rate. Source: Frankfurter (ECB reference rates; free, no key). A past date gets that day's
// rate (weekends/holidays resolve to the previous business day); today or later gets the latest.
//
// Asked as USD -> currency and inverted: the API returns 5 decimals, and INR->USD would be
// 0.01033 (0.1% resolution) where USD->INR is 96.80 (0.001%).
const cache = new Map()

function usdRate(currency, date) {
  if (!currency || currency === 'USD') return Promise.resolve(1)
  const today = new Date().toISOString().slice(0, 10)
  const day = date && date.slice(0, 10) < today ? date.slice(0, 10) : 'latest'
  const key = `${currency}|${day === 'latest' ? 'latest@' + today : day}`
  if (!cache.has(key)) {
    cache.set(key, fetch(`https://api.frankfurter.dev/v1/${day}?from=USD&to=${encodeURIComponent(currency)}`,
      { signal: AbortSignal.timeout(10_000) })
      .then(async (r) => {
        const per = r.ok ? (await r.json()).rates?.[currency] : null
        if (!per) throw new Error(`no USD->${currency} rate for ${day} (HTTP ${r.status})`)
        return 1 / per
      })
      .catch((e) => { cache.delete(key); throw e }))
  }
  return cache.get(key)
}

// Set fx_rate on rows that need one: non-USD and no rate/base amount given. A failed lookup
// leaves the row alone, so db.upsertTransaction reports its usual "fx_rate required" error.
async function fillRates(items, db) {
  for (const t of items) {
    if (t.fx_rate != null || t.base_amount_cents != null) continue
    const cur = t.currency || db.accountByName(t.account)?.currency || 'USD'
    if (cur === 'USD') continue
    try { t.fx_rate = await usdRate(cur, t.posted_at) } catch (e) { console.error(`[fx] ${e.message}`) }
  }
  return items
}

module.exports = { usdRate, fillRates }
