/// What the Activity list shows. A search goes to search_transactions, which has no filters,
/// so the other fields are applied to its results here; without a search they go to list_transactions.
struct TransactionFilter: Equatable, Sendable {
    var query = ""
    var period = TransactionPeriod.allTime
    var account: String?
    /// A category as the API names it; "(uncategorized)" means rows with none.
    var category: String?
    var direction: Direction?

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isFiltered: Bool {
        period != .allTime || account != nil || category != nil || direction != nil
    }

    func matches(_ transaction: LedgerTransaction) -> Bool {
        // posted_at is text and the bounds are text, exactly as the server compares them.
        let range = period.range()
        if let from = range.from, transaction.postedAt < from { return false }
        if let to = range.to, transaction.postedAt >= to { return false }
        if let account, transaction.account != account { return false }
        if let category {
            if category == CategoryScope.uncategorized {
                if transaction.category != nil { return false }
            } else if transaction.category != category {
                return false
            }
        }
        if let direction, transaction.direction != direction { return false }
        return true
    }
}
