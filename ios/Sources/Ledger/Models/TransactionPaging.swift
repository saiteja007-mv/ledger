/// Reads a long, newest-first transaction list in date windows.
///
/// list_transactions has no offset, and answers at most 1000 rows. A full page is followed by another
/// query whose exclusive upper date is the last row's `posted_at`, so nothing is silently cut.
enum TransactionPaging {
    /// list_transactions' own maximum.
    static let pageSize = 1000
    /// 5000 rows: more than any month or filter holds, and the line past which the screen says it stopped.
    static let maxPages = 5

    /// `fetch` gets the exclusive upper date (nil for no upper bound) and returns one page, newest first.
    static func collect(
        upper: String?,
        pageSize: Int = pageSize,
        maxPages: Int = maxPages,
        fetch: (String?) async throws -> [LedgerTransaction]
    ) async throws -> TransactionList {
        var rows: [LedgerTransaction] = []
        var seen = Set<Int>()
        var bound = upper
        for _ in 0..<maxPages {
            let page = try await fetch(bound)
            let before = rows.count
            for row in page where seen.insert(row.id).inserted {
                rows.append(row)
            }
            if page.count < pageSize {
                return TransactionList(rows: rows, isTruncated: false)
            }
            // A full page: there may be more. If it added nothing new (one timestamp filling a whole page)
            // the window can't advance, so stop and say so.
            guard rows.count > before, let last = page.last?.postedAt else { break }
            // `to` is exclusive and the "~" sorts after any stamp, so rows tied with `last` come back
            // (and are dropped above) instead of being skipped.
            let next = last + "~"
            bound = upper.map { min($0, next) } ?? next
        }
        return TransactionList(rows: rows, isTruncated: true)
    }
}
