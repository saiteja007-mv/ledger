import Foundation

/// Amounts of an item as the Inventory and Shopping List screens print them.
enum Quantity {
    /// "0.25 lb", or "×3" for things counted one by one.
    static func text(_ value: Double, unit: String?) -> String {
        guard let unit = measuredUnit(unit) else { return "×\(number(value))" }
        return "\(number(value)) \(unit)"
    }

    /// The number without noise: "1", "0.25", never "1.0000001".
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// The unit when the amount is measured (gal, lb, oz); nil for things counted one by one ("each", or none).
    static func measuredUnit(_ unit: String?) -> String? {
        guard let unit, !unit.isEmpty, unit != "each" else { return nil }
        return unit
    }
}
