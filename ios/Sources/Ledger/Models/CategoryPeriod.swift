import Foundation

/// One calendar month as the ledger bounds it: `from` is its first day and `to` the first day of
/// the next month, exclusive. These are the `from` and `to` of list_transactions, and the same window
/// budget_status and category_breakdown total over, so a list and the number above it always agree.
///
/// A month is named by its "YYYY-MM" label. The label comes from the server (budget_status's
/// `period_label`, spending_summary's `from`), so the phone's time zone never moves a boundary:
/// `posted_at` is wall-clock text and compares as text.
struct CategoryPeriod: Hashable, Sendable {
    /// "2026-10"
    let month: String
    /// "2026-10-01"
    let from: String
    /// "2026-11-01", exclusive.
    let to: String

    private let year: Int
    private let monthNumber: Int

    init?(month label: String) {
        let parts = label.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month)
        else { return nil }
        self.init(year: year, month: month)
    }

    /// The month of a "YYYY-MM-DD" date or a "YYYY-MM-DDTHH:MM:SS" stamp.
    init?(containing text: String) {
        self.init(month: String(text.prefix(7)))
    }

    /// The month `date` falls in, on the wall clock of `calendar`'s time zone.
    init(containing date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
    }

    private init(year: Int, month: Int) {
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        self.year = year
        self.monthNumber = month
        self.month = "\(year)-\(two(month))"
        from = "\(year)-\(two(month))-01"
        to = month == 12 ? "\(year + 1)-01-01" : "\(year)-\(two(month + 1))-01"
    }

    func isCurrent(now: Date = .now, calendar: Calendar = .current) -> Bool {
        self == CategoryPeriod(containing: now, calendar: calendar)
    }

    /// "October 2026".
    func title(locale: Locale = .current) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let noon = utc.date(from: DateComponents(year: year, month: monthNumber, day: 15, hour: 12)) ?? .now
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: utc, timeZone: utc.timeZone)
            .month(.wide).year()
        return noon.formatted(style)
    }
}
