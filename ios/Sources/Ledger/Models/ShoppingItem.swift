import Foundation

/// One open row of the shopping list. Prices are cents per `unit`.
struct ShoppingItem: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let itemKey: String?
    let unit: String?
    let name: String
    let qty: Double?
    let source: Source
    let reason: String?
    let lastPriceCents: Int?
    let cheapestMerchant: String?

    /// Who put the row on the list.
    enum Source: String, Decodable, Hashable, Sendable {
        case rule
        case ai
        case user
        /// A source a newer server sends that this app doesn't know.
        case unknown

        init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    /// Typed by the owner: it is removed. Rows from the rules or Claude are dismissed.
    var isOwner: Bool { source == .user }

    /// The owner's words stay as typed; names from receipts are lower case.
    var displayName: String { isOwner ? name : name.capitalized }

    /// "1 gal" or "×12".
    var qtyText: String? {
        qty.map { Quantity.text($0, unit: unit) }
    }

    /// "$3.49/gal · cheapest at Corner Market"; nil when the item has no price yet.
    var priceHint: String? {
        guard let lastPriceCents else { return nil }
        let per = unit.flatMap { $0.isEmpty ? nil : $0 } ?? "unit"
        let price = "\(Money.text(lastPriceCents))/\(per)"
        guard let cheapestMerchant else { return price }
        return String(localized: "\(price) · cheapest at \(cheapestMerchant)")
    }
}
