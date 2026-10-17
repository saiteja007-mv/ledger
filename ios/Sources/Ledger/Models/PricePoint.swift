import Foundation

/// One purchase of an item, from item_price_history.
struct PricePoint: Decodable, Identifiable, Sendable {
    let id: Int
    let receiptId: Int
    let name: String
    let qty: Double
    let unit: String
    let unitPriceCents: Int?
    let totalCents: Int
    let merchant: String?
    let purchasedAt: String?

    var date: Date? {
        purchasedAt.flatMap { LedgerDate.parse($0) }
    }
}
