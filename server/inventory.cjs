// How fast a household item gets used, learned from how often it is rebought.
// Pure functions, no database: db.cjs feeds purchases in and shapes the rows that come out.
// The rules are written up in docs/superpowers/specs/2026-10-29-inventory-shopping-list-design.md.
const RUNNING_LOW_USED = 0.8   // this much of the last pack gone ...
const RUNNING_LOW_DAYS = 2     // ... or this few days left -> running low
const LIST_DAYS = 3            // shopping list suggests an item this close to running out
const LAPSE_FACTOR = 3         // no rebuy for 3x the expected life ...
const LAPSE_MIN_DAYS = 30      // ... and at least this long -> probably stopped buying it
const CYCLES = 6               // typical life = median of the last 6 completed cycles

// Lines that are not products. Everything else on a receipt may be a consumable.
const NOT_A_PRODUCT = /\b(tax|fee|deposit|bag|tip|service charge|coupon|discount)\b/i
const isProductLine = (name, total_cents) => total_cents > 0 && !NOT_A_PRODUCT.test(name || '')

// Whole days since 1970 for a local 'YYYY-MM-DD…' string. Date.UTC (never new Date(s)) so
// neither the time of day nor a DST change can shift the day.
const dayNum = (s) => { const [y, m, d] = String(s).slice(0, 10).split('-').map(Number); return Date.UTC(y, m - 1, d) / 864e5 }

const round2 = (x) => Math.round(x * 100) / 100
const median = (a) => { const s = [...a].sort((x, y) => x - y), h = s.length >> 1; return s.length % 2 ? s[h] : (s[h - 1] + s[h]) / 2 }

// purchases: { date, qty }[]  usedUp: date[]  tracked: null (auto) | 0 | 1  today: 'YYYY-MM-DD'
// Every field is always present; the ones that do not apply to the status are null.
function estimateItem({ purchases, usedUp = [], tracked = null, today }) {
  // same-day purchases merge into one; a missing or zero qty counts as one pack
  const byDay = new Map()
  for (const p of purchases) { const d = String(p.date).slice(0, 10); byDay.set(d, (byDay.get(d) || 0) + (p.qty > 0 ? p.qty : 1)) }
  const buys = [...byDay].sort(([a], [b]) => (a < b ? -1 : 1)).map(([date, qty]) => ({ date, qty, n: dayNum(date) }))
  const ups = usedUp.map((u) => dayNum(u)).sort((a, b) => a - b)

  // Days per unit for each completed cycle. Cycle i owns the first Used up in (t_i, t_i+1]
  // (a same-day Used up closes the earlier cycle); with none, a rebuy ends it. The latest
  // cycle only completes once it has a Used up.
  const gaps = buys.flatMap((b, i) => {
    const next = buys[i + 1]?.n ?? Infinity
    const end = ups.find((u) => u > b.n && u <= next) ?? (next === Infinity ? null : next)
    return end == null ? [] : [(end - b.n) / b.qty]
  })
  const last = buys.at(-1)
  const L = gaps.length ? median(gaps.slice(-CYCLES)) : null
  const out = (status, x = {}) => ({
    status, last_bought: last.date, last_qty: last.qty, qty_left: null, used_pct: null, days_left: null,
    lasts_days: null, days_per_unit: null, cycles: gaps.length, ...x,
  })

  if (tracked === 0) return out('off')
  if (tracked !== 1 && buys.length < 2) return out('once')   // rebuying is what makes it a consumable
  if (L == null) return out('learning')

  const E = L * last.qty, now = dayNum(today)
  const life = { days_per_unit: round2(L), lasts_days: Math.round(E) }
  const gone = { ...life, qty_left: 0, used_pct: 100, days_left: 0 }
  // quiet since the later of the last purchase and the last Used up
  const quiet = now - Math.max(last.n, ups.at(-1) ?? -Infinity)
  if (quiet > LAPSE_FACTOR * E && quiet >= LAPSE_MIN_DAYS) return out('lapsed', gone)
  if (ups.some((u) => u > last.n)) return out('used_up', gone)

  const age = Math.max(0, now - last.n), used = Math.min(1, age / E), left = Math.max(0, E - age)
  return out(used >= RUNNING_LOW_USED || left <= RUNNING_LOW_DAYS ? 'running_low' : 'in_stock', {
    ...life, qty_left: round2(last.qty * (1 - used)), used_pct: Math.round(used * 100), days_left: Math.round(left),
  })
}

module.exports = { isProductLine, estimateItem, dayNum,
  RUNNING_LOW_USED, RUNNING_LOW_DAYS, LIST_DAYS, LAPSE_FACTOR, LAPSE_MIN_DAYS, CYCLES }
