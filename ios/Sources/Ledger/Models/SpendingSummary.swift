/// Income, expense and net for a period, in USD cents. Transfers are excluded.
struct SpendingSummary: Decodable, Sendable {
    /// The window the server totalled: this month's first day, and the next month's, exclusive.
    let from: String?
    let to: String?
    let incomeCents: Int
    let expenseCents: Int
    let netCents: Int
    let transfersExcluded: Int

    /// The month this summary covers; the category list under a total from the same window uses it.
    var period: CategoryPeriod? {
        from.flatMap { CategoryPeriod(containing: $0) }
    }
}
