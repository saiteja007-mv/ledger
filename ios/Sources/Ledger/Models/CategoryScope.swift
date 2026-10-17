import Foundation

/// What a category list is about: the expenses of one category (or of all spending) in one month.
/// It is the cache key for the list, and it knows the Activity filter that shows the same rows.
struct CategoryScope: Hashable, Sendable {
    /// budget_status and category_breakdown name rows without a category this.
    static let uncategorized = "(uncategorized)"
    /// The budget category that limits all spending together.
    static let total = "Total"

    /// The category exactly as the API reports it; nil for all spending.
    let category: String?
    let period: CategoryPeriod

    /// `name` is a category as budget_status or category_breakdown reports it.
    init(name: String, period: CategoryPeriod) {
        category = name == Self.total ? nil : name
        self.period = period
    }

    var isUncategorized: Bool {
        category == Self.uncategorized
    }

    var title: String {
        category.map(CategoryName.display) ?? String(localized: "All spending")
    }

    /// Activity filtered to these rows: expenses, as every category total counts only expenses.
    func activityFilter(now: Date = .now, calendar: Calendar = .current) -> TransactionFilter {
        var filter = TransactionFilter()
        filter.category = category
        filter.direction = .expense
        filter.period = TransactionPeriod.forMonth(period, now: now, calendar: calendar)
        return filter
    }
}
