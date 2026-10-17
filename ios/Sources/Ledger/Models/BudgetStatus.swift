import SwiftUI

/// One budget against this month's spending, from budget_status. Category "Total" is the overall limit.
struct BudgetStatus: Decodable, Identifiable, Hashable, Sendable {
    let category: String
    let period: String
    /// The month the spending was totalled over, "YYYY-MM".
    let periodLabel: String?
    let limitCents: Int
    let spentCents: Int
    let remainingCents: Int
    let pctUsed: Double?
    /// "ok", "warning" (80% or more) or "over".
    let status: String

    var id: String { "\(category)|\(period)" }

    var isTotal: Bool { category == CategoryScope.total }

    /// The expenses behind `spentCents`: this category (or all spending) over the month budget_status totalled.
    /// The ledger totals every budget over the whole month, weekly ones included, so the list does too.
    /// Without a label from the server, the phone's current month stands in.
    func scope(now: Date = .now) -> CategoryScope {
        let month = periodLabel.flatMap { CategoryPeriod(month: $0) } ?? CategoryPeriod(containing: now)
        return CategoryScope(name: category, period: month)
    }

    var isWeekly: Bool { period == "weekly" }

    var tint: Color {
        switch status {
        case "over": .red
        case "warning": .orange
        default: Theme.accent
        }
    }

    /// A shape as well as a color, for Differentiate Without Color.
    var systemImage: String {
        switch status {
        case "over": "exclamationmark.octagon.fill"
        case "warning": "exclamationmark.triangle.fill"
        default: "checkmark.circle.fill"
        }
    }
}
