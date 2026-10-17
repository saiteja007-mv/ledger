/// What was read off a receipt photo on upload. It can differ from the ledger fields when only your share was booked.
struct Bill: Decodable, Sendable {
    let isReceipt: Bool?
    let merchant: String?
    let storeAddress: String?
    let purchasedAt: String?
    let payment: String?
    let lineItems: [LineItem]?
    let subtotal: Double?
    let tax: Double?
    let total: Double?
    /// Problems that could make a value wrong: cut off, unreadable, ambiguous.
    let notes: String?
}
