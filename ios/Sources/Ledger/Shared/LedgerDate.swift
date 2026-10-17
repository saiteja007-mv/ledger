import Foundation

/// The ledger's date formats. posted_at is local wall-clock time with no zone ("where you paid"),
/// so all of these read and write it in the phone's current time zone unless a zone is given.
enum LedgerDate {
    /// "YYYY-MM-DDTHH:MM:SS"
    private static func stampStyle(_ timeZone: TimeZone) -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().time(includingFractionalSeconds: false)
    }

    /// "YYYY-MM-DD"
    private static func dayStyle(_ timeZone: TimeZone) -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()
    }

    static func stamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(stampStyle(timeZone))
    }

    static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(dayStyle(timeZone))
    }

    /// Reads "YYYY-MM-DDTHH:MM:SS" or "YYYY-MM-DD" (anything after is ignored).
    static func parse(_ text: String, timeZone: TimeZone = .current) -> Date? {
        if text.count >= 19, let date = try? stampStyle(timeZone).parse(String(text.prefix(19))) { return date }
        return try? dayStyle(timeZone).parse(String(text.prefix(10)))
    }

    /// For display: the date, plus the time when the text has one.
    static func display(_ text: String) -> String {
        guard let date = parse(text) else { return text }
        return text.count >= 16
            ? date.formatted(date: .abbreviated, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
    }

    static func monthStart(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    static func adding(months: Int, to date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }
}
