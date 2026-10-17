import Foundation

/// One ledger row, as list_transactions, search_transactions and review_queue return it.
/// Amounts are positive integer cents; `direction` carries the sign.
struct LedgerTransaction: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    /// Local wall-clock time, "YYYY-MM-DDTHH:MM:SS".
    let postedAt: String
    let account: String?
    let direction: Direction
    let amountCents: Int
    let currency: String?
    /// The amount in USD when the row is in another currency.
    let baseAmount: Double?
    var category: String?
    let subcategory: String?
    let merchant: String?
    let note: String?
    let source: String?
    var reviewed: Bool?
    /// How sure whoever wrote the row was, 0-1.
    let confidence: Double?

    var title: String {
        merchant ?? category ?? String(localized: direction.label)
    }

    var date: Date? {
        LedgerDate.parse(postedAt)
    }

    var isForeign: Bool {
        (currency ?? "USD") != "USD"
    }

    /// The amount in USD cents, which is what budgets and category totals sum.
    var baseCents: Int {
        baseAmount.map { Int(($0 * 100).rounded()) } ?? amountCents
    }
}
