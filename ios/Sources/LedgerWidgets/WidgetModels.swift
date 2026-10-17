import Foundation

// Foundation only, so scripts/build-ledger.sh can compile and check this file on Linux.
// The extension is its own module and the app's model types aren't shared with it: these are the
// few fields the widgets read, decoded with `.convertFromSnakeCase` like the app does.

/// One month's totals from `spending_summary`, in USD cents. Transfers are excluded.
struct WidgetSummary: Decodable, Sendable {
    let incomeCents: Int
    let expenseCents: Int
}

/// One limit from `budget_status`. The category "Total" is the overall limit.
struct WidgetBudget: Decodable, Identifiable, Sendable {
    let category: String
    let period: String
    let limitCents: Int
    let spentCents: Int
    let remainingCents: Int
    let pctUsed: Double?
    /// "ok", "warning" (80% or more) or "over".
    let status: String

    var id: String { "\(category)|\(period)" }
    var isTotal: Bool { category == "Total" }
    var isOver: Bool { status == "over" }

    /// 0...1 for a bar; an unset limit draws empty.
    var fraction: Double {
        limitCents > 0 ? min(max(Double(spentCents) / Double(limitCents), 0), 1) : 0
    }

    var percent: Int {
        Int((pctUsed ?? (limitCents > 0 ? Double(spentCents) / Double(limitCents) * 100 : 0)).rounded())
    }

    var title: String { isTotal ? "All spending" : category }

    /// "$79 left" or "$12 over", in whole dollars.
    var leftText: String {
        isOver
            ? "\(WidgetMoney.text(-remainingCents, whole: true)) over"
            : "\(WidgetMoney.text(remainingCents, whole: true)) left"
    }
}

/// One row from `list_transactions`. Amounts are positive cents in the row's own currency.
struct WidgetTransaction: Decodable, Identifiable, Sendable {
    let id: Int
    let postedAt: String
    /// "expense", "income", "transfer_out" or "transfer_in".
    let direction: String
    let amountCents: Int
    let currency: String?
    let merchant: String?
    let category: String?
    let account: String?

    var title: String { merchant ?? category ?? account ?? "Transaction" }
    var isMoneyIn: Bool { direction == "income" || direction == "transfer_in" }
    var isTransfer: Bool { direction.hasPrefix("transfer") }
}

/// Everything the three widgets draw, fetched together so they agree.
struct WidgetSnapshot: Sendable {
    let summary: WidgetSummary
    /// budget_status order: worst first.
    let budgets: [WidgetBudget]
    /// Newest first, transfers left out.
    let recent: [WidgetTransaction]

    /// The overall limit, when one is set.
    var overall: WidgetBudget? { budgets.first(where: \.isTotal) }

    /// The overall limit first, then the worst categories: what the Budgets widget lists.
    var limits: [WidgetBudget] { budgets.filter(\.isTotal) + budgets.filter { !$0.isTotal } }

    /// What a single-limit view shows: the overall limit, or with none set, the worst category.
    var headline: WidgetBudget? { overall ?? limits.first }

    static let sample = WidgetSnapshot(
        summary: WidgetSummary(incomeCents: 482_000, expenseCents: 130_655),
        budgets: [
            WidgetBudget(category: "Total", period: "monthly", limitCents: 210_000, spentCents: 130_655,
                         remainingCents: 79_345, pctUsed: 62, status: "ok"),
            WidgetBudget(category: "Food", period: "monthly", limitCents: 25_000, spentCents: 13_858,
                         remainingCents: 11_142, pctUsed: 55, status: "ok"),
            WidgetBudget(category: "Transport", period: "monthly", limitCents: 15_000, spentCents: 8_019,
                         remainingCents: 6_981, pctUsed: 53, status: "ok"),
            WidgetBudget(category: "Groceries", period: "monthly", limitCents: 25_000, spentCents: 7_900,
                         remainingCents: 17_100, pctUsed: 32, status: "ok"),
        ],
        recent: [
            WidgetTransaction(id: 1, postedAt: "2026-10-12T12:00:00", direction: "expense", amountCents: 715,
                              currency: "USD", merchant: "Lyft", category: "Transport", account: "Checking"),
            WidgetTransaction(id: 2, postedAt: "2026-10-11T12:00:00", direction: "expense", amountCents: 4001,
                              currency: "USD", merchant: "Corner Market", category: "Groceries", account: "Checking"),
            WidgetTransaction(id: 3, postedAt: "2026-10-10T12:00:00", direction: "income", amountCents: 3527,
                              currency: "USD", merchant: nil, category: "Income", account: "Checking"),
        ]
    )
}

enum WidgetMoney {
    /// The currency symbol first, then the amount ("$7.15", "€12.00"); `whole` drops the cents for big figures.
    static func text(_ cents: Int, currency: String? = nil, whole: Bool = false) -> String {
        let style = Decimal.FormatStyle.Currency(code: currency ?? "USD")
            .precision(.fractionLength(whole ? 0 : 2))
        return (Decimal(cents) / 100).formatted(style)
    }
}
