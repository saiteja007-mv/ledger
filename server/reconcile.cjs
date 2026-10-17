// Reconciliation + budget status. Pure functions over rows the caller fetched.
//
// Reconciliation is the guard against hallucinated data. ChatGPT transcribes bank figures,
// so transactions alone can be confidently wrong. A reported balance is an independent
// anchor: if SUM(transactions) since the last balance doesn't land on the next balance,
// something was invented, dropped, or double-counted. Drift is the signal.

const cents = (v) => (v == null ? 0 : Number(v))

// Signed effect of a transaction on its own account's balance.
function delta(t) {
  switch (t.direction) {
    case 'income': case 'transfer_in': return cents(t.amount_cents)
    case 'expense': case 'transfer_out': return -cents(t.amount_cents)
    default: return 0
  }
}

// Given two balance snapshots for one account and the transactions between them,
// report whether the ledger explains the change.
function reconcileAccount({ account, from, to, opening_cents, closing_cents, transactions }) {
  const moved = transactions.reduce((a, t) => a + delta(t), 0)
  const expected = cents(opening_cents) + moved
  const drift = cents(closing_cents) - expected
  return {
    account, from, to,
    opening_cents: cents(opening_cents),
    closing_cents: cents(closing_cents),
    ledger_movement_cents: moved,
    expected_closing_cents: expected,
    drift_cents: drift,
    balanced: drift === 0,
    // A tolerance exists because rounding on FX conversion can legitimately be off by a
    // cent or two; anything larger is missing or invented data, not rounding.
    within_tolerance: Math.abs(drift) <= Math.max(2, Math.round(Math.abs(moved) * 0.0001)),
    transaction_count: transactions.length,
  }
}

// Current balance implied by the ledger alone (no snapshot needed).
function impliedBalance(transactions) {
  return transactions.reduce((a, t) => a + delta(t), 0)
}

// A budget on this reserved category is the overall monthly limit: it counts ALL spending,
// not one category's.
const TOTAL_BUDGET = 'Total'
function budgetStatus({ budgets, spendByCategory, period_label }) {
  const spent = new Map(spendByCategory.map((r) => [r.category, cents(r.cents)]))
  const all = spendByCategory.reduce((s, r) => s + cents(r.cents), 0)
  return budgets.map((b) => {
    const used = b.category === TOTAL_BUDGET ? all : (spent.get(b.category) || 0)
    const pct = b.limit_cents ? Math.round((used / b.limit_cents) * 1000) / 10 : null
    return {
      category: b.category, period: b.period, period_label: period_label ?? null,
      limit_cents: b.limit_cents, spent_cents: used,
      remaining_cents: b.limit_cents - used,
      pct_used: pct,
      status: used > b.limit_cents ? 'over' : pct != null && pct >= 80 ? 'warning' : 'ok',
    }
  }).sort((a, b) => (b.pct_used ?? -1) - (a.pct_used ?? -1))
}

// Rows an LLM wrote that a human has not confirmed. This queue is the whole reason
// `reviewed` exists — imported history is trusted, ChatGPT-sourced rows are not.
function reviewQueue(rows) {
  return rows
    .filter((r) => !r.reviewed && r.source !== 'import')
    .map((r) => ({
      id: r.id, posted_at: r.posted_at, account: r.account,
      direction: r.direction, amount_cents: r.amount_cents, currency: r.currency,
      merchant: r.merchant, category: r.category, source: r.source,
      confidence: r.confidence,
    }))
}

module.exports = { delta, reconcileAccount, impliedBalance, budgetStatus, reviewQueue, TOTAL_BUDGET }
