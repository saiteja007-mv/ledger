import Foundation

/// The groups the Inventory screen shows, in order.
enum InventorySection: CaseIterable, Identifiable, Hashable, Sendable {
    case runningLow
    case inStock
    case usedUp
    case learning
    /// Switched off, bought once, lapsed: kept so they can be switched on, collapsed by default.
    case notTracked

    var id: Self { self }

    var title: String {
        switch self {
        case .runningLow: String(localized: "Running low")
        case .inStock: String(localized: "In stock")
        case .usedUp: String(localized: "Used up")
        case .learning: String(localized: "Learning")
        case .notTracked: String(localized: "Not tracked")
        }
    }

    /// The items in screen order; a section with none is left out. Running low leads with what runs out first.
    static func groups(_ items: [InventoryItem]) -> [(section: InventorySection, items: [InventoryItem])] {
        allCases.compactMap { section in
            var rows = items.filter { $0.section == section }
            if section == .runningLow {
                rows.sort { ($0.daysLeft ?? .max, $0.name) < ($1.daysLeft ?? .max, $1.name) }
            }
            return rows.isEmpty ? nil : (section: section, items: rows)
        }
    }
}
