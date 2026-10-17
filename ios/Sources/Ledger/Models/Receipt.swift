/// A stored receipt, from list_receipts or get_receipt (which adds `bill` and `transaction`).
struct Receipt: Decodable, Identifiable, Sendable {
    let id: Int
    let merchant: String?
    let purchasedAt: String?
    let totalCents: Int?
    let tax: Double?
    let currency: String?
    let source: String?
    let transactionId: Int?
    let lineItems: [LineItem]?
    let hasImage: Bool?
    /// pending, reading, done or failed: the photo being read into a bill.
    let billStatus: String?
    let billError: String?
    let bill: Bill?
    let transaction: LedgerTransaction?

    var title: String {
        merchant ?? bill?.merchant ?? String(localized: "Receipt \(id)")
    }

    var isReading: Bool {
        billStatus == "pending" || billStatus == "reading"
    }

    /// The ledger's items, or the bill's when this receipt is a split share itemised elsewhere.
    var items: [LineItem] {
        if let lineItems, !lineItems.isEmpty { lineItems } else { bill?.lineItems ?? [] }
    }
}
