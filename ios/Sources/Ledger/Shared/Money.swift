import Foundation

/// Cents to display text. Decimal, so 1999 cents is exactly $19.99.
enum Money {
    static func text(_ cents: Int, currency: String? = nil) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currency ?? "USD"))
    }

    static func text(_ cents: Double, currency: String? = nil) -> String {
        text(Int(cents.rounded()), currency: currency)
    }

    /// "+$12.50" for money in, "−$12.50" for money out.
    static func signed(_ cents: Int, currency: String?, direction: Direction) -> String {
        "\(direction.sign > 0 ? "+" : "−")\(text(cents, currency: currency))"
    }

    /// A typed amount in the phone's own number format ("1,234.50" or "1.234,50"); nil when it isn't one.
    static func parseAmount(_ text: String) -> Double? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return try? Double(text, format: .number)
    }

    /// Dollars as the API sends them in receipts and bills.
    static func dollars(_ value: Double, currency: String? = nil) -> String {
        value.formatted(.currency(code: currency ?? "USD"))
    }
}
