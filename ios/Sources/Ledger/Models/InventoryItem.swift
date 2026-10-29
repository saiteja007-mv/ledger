import Foundation

/// One consumable from the `inventory` tool: what is probably left, how fast it goes, and what it cost last.
/// Prices are cents per `unit`. A field that doesn't fit the item's status is null (a learning item has no `qtyLeft`).
struct InventoryItem: Decodable, Identifiable, Hashable, Sendable {
    let itemKey: String
    let unit: String
    let name: String
    /// The owner's override: `auto`, `on` or `off`.
    let tracked: String
    let status: Status
    /// YYYY-MM-DD.
    let lastBought: String?
    let lastQty: Double?
    let qtyLeft: Double?
    let usedPct: Int?
    let daysLeft: Int?
    let lastsDays: Int?
    let daysPerUnit: Double?
    /// Completed buy-to-empty cycles the estimate is based on.
    let cycles: Int
    let lastPriceCents: Int?
    let cheapestMerchant: String?

    enum Status: String, Decodable, Hashable, Sendable {
        case learning
        case inStock = "in_stock"
        case runningLow = "running_low"
        case usedUp = "used_up"
        case lapsed
        case off
        case once
        /// A status a newer server sends that this app doesn't know: shown, never a failed list.
        case unknown

        init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    var id: String { "\(itemKey)|\(unit)" }

    /// Receipt lines are lower case.
    var displayName: String { name.capitalized }

    var section: InventorySection {
        switch status {
        case .runningLow: .runningLow
        case .inStock: .inStock
        case .usedUp: .usedUp
        case .learning: .learning
        case .lapsed, .off, .once, .unknown: .notTracked
        }
    }

    /// Switched off, or bought once so far: the owner can start following it.
    var canTrack: Bool { status == .off || status == .once }

    /// Followed now, so the owner can stop. A lapsed item comes back by itself when it is bought again.
    var canStopTracking: Bool { section != .notTracked }

    /// An estimate exists, so the usage bar means something.
    var hasEstimate: Bool { status == .inStock || status == .runningLow || status == .usedUp }

    /// Followed and in use, so "Used up" means something (on a learning item it closes the first cycle).
    var canMarkUsedUp: Bool { status == .inStock || status == .runningLow || status == .learning }

    /// "0.2 gal left", "9 left" or "Used up"; nil while the app is still learning the item.
    var leftText: String? {
        switch status {
        case .usedUp:
            return String(localized: "Used up")
        case .inStock, .runningLow:
            guard let qtyLeft else { return nil }
            let amount = Quantity.measuredUnit(unit).map { "\(Quantity.number(qtyLeft)) \($0)" } ?? Quantity.number(qtyLeft)
            return String(localized: "\(amount) left")
        default:
            return nil
        }
    }

    /// "~2 days left", or "Due now" at zero.
    var daysLeftText: String? {
        guard status == .inStock || status == .runningLow else { return nil }
        guard let daysLeft, daysLeft > 0 else { return String(localized: "Due now") }
        return String(localized: "~\(Self.days(daysLeft)) left")
    }

    /// "lasts ~12 days": how long the last purchase is expected to last.
    var lastsText: String? {
        guard canStopTracking, let lastsDays else { return nil }
        return String(localized: "lasts ~\(Self.days(lastsDays))")
    }

    /// 0 to 1, for the usage bar.
    var usedFraction: Double {
        min(max(Double(usedPct ?? (status == .usedUp ? 100 : 0)) / 100, 0), 1)
    }

    /// Why the row isn't a normal tracked one; nil for those.
    var statusLabel: String? {
        switch status {
        case .learning: String(localized: "Learning")
        case .once: String(localized: "Single purchase")
        case .lapsed: String(localized: "Lapsed")
        case .off, .unknown: String(localized: "Not tracked")
        case .inStock, .runningLow, .usedUp: nil
        }
    }

    /// The row's second line: how much is left, or why there is no estimate ("Learning · bought Oct 20, 2026").
    var subtitle: String {
        if let leftText { return leftText }
        let when = lastBought.map { String(localized: "bought \(LedgerDate.display($0))") }
        return [statusLabel, when].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Bought Oct 20, 2026 · ×1".
    var boughtText: String? {
        guard let lastBought else { return nil }
        let when = String(localized: "Bought \(LedgerDate.display(lastBought))")
        guard let lastQty else { return when }
        return "\(when) · \(Quantity.text(lastQty, unit: unit))"
    }

    /// "$3.49/gal".
    var priceText: String? {
        lastPriceCents.map { "\(Money.text($0))/\(unit)" }
    }

    private static func days(_ count: Int) -> String {
        count == 1 ? String(localized: "1 day") : String(localized: "\(count) days")
    }
}
