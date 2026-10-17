/// One grocery item across every stored receipt, from item_prices. Prices are cents per `unit`.
struct PriceItem: Decodable, Identifiable, Hashable, Sendable {
    let itemKey: String
    let name: String
    let unit: String
    let purchases: Int
    let merchants: Int
    let minCents: Double?
    let avgCents: Double?
    let maxCents: Double?
    let lastCents: Double?
    let prevCents: Double?
    /// Latest unit price against the one before, in percent.
    let changePct: Double?
    let lastMerchant: String?
    let lastAt: String?

    var id: String { "\(itemKey)|\(unit)" }
}
