import Foundation

/// The date window of the Activity list.
enum TransactionPeriod: Hashable, Identifiable, Sendable {
    case thisMonth
    case lastMonth
    case last90Days
    case allTime
    /// One specific month, such as the month of a budget being looked into.
    case month(CategoryPeriod)

    /// The periods the filter menu always offers.
    static let standard: [TransactionPeriod] = [.thisMonth, .lastMonth, .last90Days, .allTime]

    var id: Self { self }

    var label: LocalizedStringResource {
        switch self {
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .last90Days: "Last 90 days"
        case .allTime: "All time"
        case .month(let period): "\(period.title())"
        }
    }

    /// A month by its label, as "this month" or "last month" when it is one, so it reads the way the menu does.
    static func forMonth(_ period: CategoryPeriod, now: Date = .now, calendar: Calendar = .current) -> TransactionPeriod {
        let current = CategoryPeriod(containing: now, calendar: calendar)
        if period == current { return .thisMonth }
        let previous = CategoryPeriod(containing: LedgerDate.adding(months: -1, to: LedgerDate.monthStart(of: now, calendar: calendar), calendar: calendar), calendar: calendar)
        return period == previous ? .lastMonth : .month(period)
    }

    /// `[from, to)` as API dates ("YYYY-MM-DD"), nil where unbounded.
    func range(now: Date = .now, calendar: Calendar = .current) -> (from: String?, to: String?) {
        let thisMonth = LedgerDate.monthStart(of: now, calendar: calendar)
        switch self {
        case .thisMonth:
            let period = CategoryPeriod(containing: now, calendar: calendar)
            return (period.from, period.to)
        case .lastMonth:
            let period = CategoryPeriod(containing: LedgerDate.adding(months: -1, to: thisMonth, calendar: calendar), calendar: calendar)
            return (period.from, period.to)
        case .last90Days:
            let start = calendar.date(byAdding: .day, value: -90, to: now) ?? now
            return (LedgerDate.day(start, timeZone: calendar.timeZone), nil)
        case .allTime:
            return (nil, nil)
        case .month(let period):
            return (period.from, period.to)
        }
    }
}
