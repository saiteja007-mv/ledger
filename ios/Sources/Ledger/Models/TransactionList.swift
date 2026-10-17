/// Transactions fetched for one screen, and whether more exist than were fetched.
struct TransactionList: Sendable {
    var rows: [LedgerTransaction]
    /// The fetch stopped at its limit: there are more rows than `rows` holds.
    var isTruncated: Bool

    static let empty = TransactionList(rows: [], isTruncated: false)

    /// The rows' USD amounts in cents, summed as category_breakdown sums them.
    var totalCents: Int {
        rows.reduce(0) { $0 + $1.baseCents }
    }
}
