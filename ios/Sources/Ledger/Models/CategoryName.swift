import Foundation

/// How a category's raw ledger name reads, and which names are not spending categories at all.
/// The ledger moved to plain names on 2026-10-14 ("Transport", not "🚖 Transport"); a row an assistant still
/// writes with an emoji reads the same once the emoji is dropped.
enum CategoryName {
    /// Bookkeeping labels transfers and corrections carry; they are not something you spend on.
    static let bookkeeping: Set<String> = [
        "credit card bill", "credit card payment", "transfers", "transfer", "adjustment", "balance adjustment",
    ]

    /// "🚖 Transport" -> "Transport"; the API's names for no category and for every category read as words.
    static func display(_ raw: String) -> String {
        if raw == CategoryScope.uncategorized { return String(localized: "Uncategorized") }
        if raw == CategoryScope.total { return String(localized: "All spending") }
        let plain = String(raw.drop { !$0.isLetter && !$0.isNumber }).trimmingCharacters(in: .whitespaces)
        return plain.isEmpty ? raw : plain
    }

    /// Whether a name belongs in a category list or picker: not an account (a transfer leg names the other
    /// account in its category) and not bookkeeping.
    static func isSpendingCategory(_ raw: String, accountNames: Set<String>) -> Bool {
        let name = display(raw)
        if accountNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return false }
        return !bookkeeping.contains(name.lowercased())
    }

    /// One entry per category as it reads, keeping the first spelling met (lists come busiest first).
    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert(display($0).lowercased()).inserted }
    }
}
