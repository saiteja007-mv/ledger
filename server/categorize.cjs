// Rule-based categorization. Pure — takes a transaction-ish object, returns a category or null.
//
// Why rules and not an LLM: 47% of the imported history is "Other" ($21.6k across 36 rows)
// and there is NO merchant text in it (Description was empty on all 738 rows). Rules can
// only act on merchant/note, so they will do nothing for the back-catalogue — they exist for
// the ChatGPT-sourced rows that DO carry merchant names. Don't expect them to fix history.
const DEFAULT_RULES = [
  { category: 'Transport', match: ['uber', 'lyft', 'ola', 'metro', 'transit', 'bart', 'mta', 'shell', 'chevron', 'exxon', 'gas station'] },
  { category: 'Food', match: ['restaurant', 'cafe', 'coffee', 'starbucks', 'dunkin', 'mcdonald', 'chipotle', 'doordash', 'ubereats', 'grubhub', 'pizza', 'taco', 'biryani'] },
  { category: 'Groceries', match: ['walmart', 'target', 'costco', 'kroger', 'aldi', 'trader joe', 'safeway', 'patel brothers', 'grocery'] },
  { category: 'Education', match: ['tuition', 'university', 'college', 'coursera', 'udemy', 'textbook'] },
  { category: 'Rent', match: ['rent', 'landlord', 'lease', 'apartment'] },
  { category: 'Utilities', match: ['electric', 'water bill', 'internet', 'comcast', 'xfinity', 'at&t', 'verizon', 't-mobile', 'utility'] },
  { category: 'Health', match: ['pharmacy', 'cvs', 'walgreens', 'clinic', 'hospital', 'dental', 'doctor'] },
  { category: 'Subscriptions', match: ['netflix', 'spotify', 'hulu', 'disney', 'prime video', 'icloud', 'google one', 'openai', 'anthropic', 'github'] },
  { category: 'Apparel', match: ['h&m', 'zara', 'uniqlo', 'nike', 'adidas', 'clothing'] },
  { category: 'Household', match: ['ikea', 'home depot', 'lowes', 'furniture'] },
]

const norm = (s) => (s || '').toLowerCase()

// Returns { category, rule, confidence } or null. Longest match wins so "prime video"
// beats a bare "prime" appearing in an unrelated merchant.
function suggest(tx, rules = DEFAULT_RULES) {
  const hay = [norm(tx.merchant), norm(tx.note), norm(tx.subcategory)].join(' ')
  if (!hay.trim()) return null
  let best = null
  for (const r of rules) {
    for (const m of r.match) {
      if (hay.includes(m) && (!best || m.length > best.matched.length)) {
        best = { category: r.category, matched: m }
      }
    }
  }
  if (!best) return null
  // Confidence scales with how specific the matched token is — "uber" is a stronger
  // signal than "rent" appearing inside a longer note.
  return { category: best.category, rule: best.matched, confidence: Math.min(0.95, 0.55 + best.matched.length * 0.03) }
}

// Suggest for many rows without writing anything. The caller decides what to apply —
// auto-applying a guessed category to money is how you quietly corrupt a year of data.
function suggestBatch(rows, rules = DEFAULT_RULES) {
  const out = []
  for (const r of rows) {
    const s = suggest(r, rules)
    if (s) out.push({ id: r.id, current: r.category ?? null, ...s })
  }
  return out
}

module.exports = { DEFAULT_RULES, suggest, suggestBatch }
