// What belongs on the shopping list, as pure functions. db.cjs stores the rows and feeds in inventory().
// The rules are written up in docs/superpowers/specs/2026-10-29-inventory-shopping-list-design.md.
const { LIST_DAYS } = require('./inventory.cjs')

const NAME_MAX = 80      // names and keys are clipped to this, whoever typed them
const REASON_MAX = 200
const MAX_AI_ADDS = 40   // one AI run may add at most this many items

// lapsed / off / once / learning never qualify: nothing there is known to be running out
const isLow = (i) => i.status === 'used_up' || i.status === 'running_low' ||
  (i.status === 'in_stock' && i.days_left != null && i.days_left <= LIST_DAYS)
const why = (i) => i.status === 'used_up' ? 'used up' : i.days_left == null ? 'running low'
  : `~${i.days_left} ${i.days_left === 1 ? 'day' : 'days'} left`

// items: inventory() rows -> what the rules would put on the list, qty = the last pack bought.
const ruleSuggestions = (items) => items.filter(isLow).map((i) =>
  ({ item_key: i.item_key, unit: i.unit, name: i.name, qty: i.last_qty, reason: why(i) }))

const clip = (s, n) => String(s ?? '').trim().slice(0, n)
// A quantity is a number above zero; anything else (negative, text, missing) means "unspecified".
// Above QTY_MAX is clipped to it: no household buys 10^9 of anything, and it keeps the total sane.
const QTY_MAX = 999
const cleanQty = (q) => (Number.isFinite(Number(q)) && Number(q) > 0 ? Math.min(QTY_MAX, Number(q)) : null)

module.exports = { ruleSuggestions, clip, cleanQty, NAME_MAX, REASON_MAX, MAX_AI_ADDS }
