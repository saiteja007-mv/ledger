import SwiftUI

/// Statistics, as the kit draws it: a Graph / List switch, the picked period's total, and either the ring with a
/// chip per category or the category list. Under them, income and expenses over time (tap a bar to pick the
/// period the total, ring, list and transactions show) and the budgets as monthly limits.
struct AnalysisView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var mode = StatsMode.graph
    @State private var selected = 0
    @State private var range = AnalysisRange.monthly
    @State private var buckets: Loadable<[AnalysisBucket]> = .loading
    /// Expense by category over the picked window: what the ring and the list show.
    @State private var windowBreakdown: Loadable<[CategoryTotal]> = .loading
    /// Every transaction since the first window began, newest first, for the picked window's list.
    @State private var rows: [LedgerTransaction] = []
    /// The window the bars have picked; the current one when nil.
    @State private var picked: Int?

    /// Most rows the picked window lists before "Show all in Payments".
    private static let listLimit = 15
    @State private var sort = RowSort.newest

    /// How the picked window's transactions are ordered. Amounts compare in USD, so mixed currencies
    /// order by what they're worth.
    enum RowSort: CaseIterable, Hashable {
        case newest, oldest, largest, smallest

        var title: String {
            switch self {
            case .newest: String(localized: "Newest first")
            case .oldest: String(localized: "Oldest first")
            case .largest: String(localized: "Largest first")
            case .smallest: String(localized: "Smallest first")
            }
        }

        func areInOrder(_ a: LedgerTransaction, _ b: LedgerTransaction) -> Bool {
            let (dateA, dateB) = (a.date ?? .distantPast, b.date ?? .distantPast)
            switch self {
            case .newest: return dateA > dateB
            case .oldest: return dateA < dateB
            case .largest: return a.baseCents != b.baseCents ? a.baseCents > b.baseCents : dateA > dateB
            case .smallest: return a.baseCents != b.baseCents ? a.baseCents < b.baseCents : dateA > dateB
            }
        }
    }

    enum StatsMode: Hashable {
        case graph, list
    }

    var body: some View {
        NavigationStack {
            KitScreen(String(localized: "Statistics"), trailing: { rangeMenu }) {
                ScrollView {
                    VStack(spacing: 0) {
                        // The bars pick the period everything under them is about, so they come first.
                        spendingOverTime
                        KitSegmented(
                            selection: $mode,
                            options: [(value: StatsMode.graph, title: String(localized: "Graph")),
                                      (value: StatsMode.list, title: String(localized: "List"))]
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        total
                        categories
                        if buckets.value?.isEmpty == false {
                            windowRows(pickedIndex)
                                .padding(.horizontal, 20)
                                .padding(.top, 26)
                        }
                        limits
                    }
                    .padding(.bottom, 24)
                }
                .refreshable {
                    store.categoryTransactions.invalidate()
                    async let shared: Void = store.refresh()
                    async let own: Void = load()
                    async let breakdown: Void = loadBreakdown()
                    _ = await (shared, own, breakdown)
                }
            }
            .ledgerDestinations()
            .task(id: LoadKey(range: range, revision: store.revision)) {
                await load()
            }
            .task(id: BreakdownKey(range: range, index: pickedIndex, revision: store.revision)) {
                await loadBreakdown()
            }
            .onChange(of: range) { picked = nil }
            .onChange(of: pickedIndex) { selected = 0 }
        }
    }

    private struct LoadKey: Hashable {
        let range: AnalysisRange
        let revision: Int
    }

    private struct BreakdownKey: Hashable {
        let range: AnalysisRange
        let index: Int
        let revision: Int
    }

    private var windows: [AnalysisRange.Window] {
        range.windows()
    }

    /// The bar the ring, list and totals are for: the one tapped, else the current window.
    private var pickedIndex: Int {
        min(picked ?? windows.count - 1, windows.count - 1)
    }

    private var pickedWindow: AnalysisRange.Window? {
        windows.indices.contains(pickedIndex) ? windows[pickedIndex] : nil
    }

    /// Where a category's rows can be opened: months only, since the category screen is a month's.
    private func scope(_ category: String) -> CategoryScope? {
        guard let window = pickedWindow, range == .monthly || range == .year else { return nil }
        return CategoryScope(name: category, period: CategoryPeriod(containing: window.start))
    }

    private var rangeMenu: some View {
        Menu {
            Picker("Show", selection: $range) {
                ForEach(AnalysisRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
        } label: {
            KitIconView(icon: .calendar, height: 24, color: KitColor.label.color)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Period")
        .padding(.trailing, 4)
    }

    // MARK: Total

    private var total: some View {
        VStack(spacing: 2) {
            if let all = buckets.value, all.indices.contains(pickedIndex) {
                KitAmountView(cents: Int((all[pickedIndex].expense * 100).rounded()), size: .medium)
            } else {
                Text("–").font(.kitHeading)
            }
            Text("Total spent for \(pickedWindow?.title ?? store.period.title())")
                .font(.kitSmall)
                .foregroundStyle(KitColor.secondary.color)
        }
        .padding(.top, 26)
        .padding(.bottom, 10)
    }

    // MARK: Categories

    @ViewBuilder
    private var categories: some View {
        switch windowBreakdown {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 280).padding(.top, 8)
        case .failed(let error):
            InlineError(error: error).padding(.top, 20)
        case .loaded(let totals) where totals.isEmpty:
            Text("No spending in this period.")
                .font(.kitSmall)
                .foregroundStyle(KitColor.secondary.color)
                .padding(.vertical, 40)
        case .loaded(let totals):
            switch mode {
            case .graph: graph(totals)
            case .list: list(totals)
            }
        }
    }

    private func graph(_ totals: [CategoryTotal]) -> some View {
        let index = min(selected, totals.count - 1)
        let current = totals[index]
        return VStack(spacing: 18) {
            ZStack {
                KitRing(fractions: totals.map { Double($0.totalCents) }, selected: index)
                KitAmountView(cents: current.totalCents, size: .large)
            }
            .frame(height: 280)
            .padding(.horizontal, 36)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(current.category), \(Money.text(current.totalCents))"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(totals.enumerated()), id: \.element.id) { offset, total in
                        chip(total, isSelected: offset == index)
                            .onTapGesture { selected = offset }
                    }
                }
                .padding(.horizontal, 20)
            }

            if let scope = scope(current.category) {
                NavigationLink(value: Route.category(scope)) {
                    Text("See \(displayName(current.category)) transactions")
                        .font(.kitSmallMedium)
                        .foregroundStyle(KitColor.accent.color)
                }
            }
        }
        .padding(.top, 8)
    }

    private func chip(_ total: CategoryTotal, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            KitAvatar(category: total.category)
            Text(displayName(total.category)).font(.kitBodyMedium).lineLimit(1)
        }
        .foregroundStyle(KitColor.label.color)
        .padding(6)
        .padding(.trailing, 10)
        .background(isSelected ? KitColor.tintStrong.color : KitColor.surface.color, in: .capsule)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func list(_ totals: [CategoryTotal]) -> some View {
        let sum = max(totals.reduce(0) { $0 + $1.totalCents }, 1)
        return VStack(spacing: 22) {
            ForEach(totals) { total in
                let row = HStack(alignment: .center, spacing: 14) {
                    KitAvatar(category: total.category, size: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(displayName(total.category)).font(.kitBodyMedium)
                        Text("\(Int((Double(total.totalCents) / Double(sum) * 100).rounded()))%")
                            .font(.kitSmall)
                            .foregroundStyle(KitColor.secondary.color)
                    }
                    Spacer(minLength: 8)
                    Text("- " + Money.text(total.totalCents))
                        .font(.kitBodyMedium)
                        .monospacedDigit()
                }
                .foregroundStyle(KitColor.label.color)
                .contentShape(.rect)
                if let scope = scope(total.category) {
                    NavigationLink(value: Route.category(scope)) { row }
                        .buttonStyle(.plain)
                } else {
                    row
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func displayName(_ category: String) -> String {
        CategoryName.display(category)
    }

    // MARK: Over time

    @ViewBuilder
    private var spendingOverTime: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Income & Expenses").font(.kitSubtitle)
            switch buckets {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            case .failed(let error):
                ErrorStateView(error: error, retry: load)
            case .loaded(let buckets) where buckets.isEmpty:
                EmptyView()
            case .loaded(let buckets):
                let index = min(picked ?? buckets.count - 1, buckets.count - 1)
                KitBars(
                    bars: buckets.map {
                        KitBars.Bar(id: $0.id, label: $0.label, value: $0.expense, valueText: Money.text($0.expense * 100))
                    },
                    selected: index,
                    onSelect: { picked = $0 }
                )
                HStack {
                    figure(title: "Income", cents: Int((buckets[index].income * 100).rounded()), positive: true)
                    Spacer()
                    figure(title: "Expense", cents: Int((buckets[index].expense * 100).rounded()), positive: false)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// The picked window's income and expense rows, newest first (transfers are left out of the totals above,
    /// so they're left out here too).
    @ViewBuilder
    private func windowRows(_ index: Int) -> some View {
        let windows = range.windows()
        if windows.indices.contains(index) {
            let window = windows[index]
            let inWindow = rows
                .filter { row in
                    guard let date = row.date, date >= window.start, date < window.end else { return false }
                    return row.direction == .income || row.direction == .expense
                }
                .sorted(by: sort.areInOrder)
            // A day or a week is short enough to list whole; a month or a year hands over to Payments.
            let isMonths = range == .monthly || range == .year
            let shown = isMonths ? Array(inWindow.prefix(Self.listLimit)) : inWindow
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(window.title).font(.kitSubtitle)
                    Spacer()
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(RowSort.allCases, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        Label(sort.title, systemImage: "arrow.up.arrow.down")
                            .font(.kitSmallMedium)
                            .foregroundStyle(KitColor.accent.color)
                    }
                    .accessibilityLabel("Sort transactions")
                }
                .padding(.top, 10)
                if inWindow.isEmpty {
                    Text("Nothing logged in this period.")
                        .font(.kitSmall)
                        .foregroundStyle(KitColor.secondary.color)
                }
                ForEach(shown) { transaction in
                    NavigationLink(value: Route.transaction(transaction)) {
                        KitTransactionRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                }
                if isMonths, inWindow.count > shown.count {
                    Button("Show all \(inWindow.count) in Payments") {
                        var filter = TransactionFilter()
                        filter.period = .month(CategoryPeriod(containing: window.start))
                        navigator.showActivity(filter)
                    }
                    .font(.kitSmallMedium)
                    .foregroundStyle(KitColor.accent.color)
                }
            }
        }
    }

    private func figure(title: LocalizedStringKey, cents: Int, positive: Bool) -> some View {
        VStack(alignment: positive ? .leading : .trailing, spacing: 0) {
            Text(title).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
            Text(Money.text(cents))
                .font(.kit(.medium, 20, relativeTo: .title3))
                .foregroundStyle(positive ? KitColor.positive.color : KitColor.label.color)
        }
    }

    // MARK: Limits

    @ViewBuilder
    private var limits: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Monthly limits").font(.kitSubtitle)
                Spacer()
                NavigationLink(value: Route.budgets) {
                    Text(store.budgets.value?.isEmpty == false ? "All budgets" : "Set a budget")
                        .font(.kitSmallMedium)
                        .foregroundStyle(KitColor.accent.color)
                }
            }
            switch store.budgets {
            case .loading:
                ProgressView()
            case .failed(let error):
                InlineError(error: error)
            case .loaded(let budgets) where budgets.isEmpty:
                Text("No budgets yet.").font(.kitSmall).foregroundStyle(KitColor.secondary.color)
            case .loaded(let budgets):
                // budget_status is sorted worst first; the overall limit always shows.
                let shown = budgets.filter(\.isTotal) + budgets.filter { !$0.isTotal }.prefix(4)
                ForEach(shown) { budget in
                    NavigationLink(value: Route.category(budget.scope())) {
                        BudgetRow(budget: budget)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
    }

    // MARK: Loading

    /// Expense by category over the picked window, for the ring and the list.
    private func loadBreakdown() async {
        guard let window = pickedWindow else { return }
        let from = LedgerDate.day(window.start)
        let to = LedgerDate.day(window.end)
        windowBreakdown = .loading
        let result = await Loadable.capture { try await LedgerAPI.categoryBreakdown(from: from, to: to) }
        guard !Task.isCancelled else { return }
        windowBreakdown = result
    }

    private func load() async {
        let windows = range.windows()
        guard let first = windows.first else { return }
        let from = LedgerDate.day(first.start)
        let result = await Loadable.capture { try await LedgerAPI.transactions(from: from, to: nil) }
        guard !Task.isCancelled else { return }
        switch result {
        case .loading: break
        case .failed(let error): buckets = .failed(error)
        case .loaded(let list):
            rows = list.rows
            buckets = .loaded(AnalysisBucket.fill(windows, from: list.rows))
        }
    }
}

/// The windows the calendar offers: the last 7 days, 6 weeks, 6 months, or 12 months.
enum AnalysisRange: CaseIterable, Hashable {
    case daily, weekly, monthly, year

    var title: String {
        switch self {
        case .daily: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .year: String(localized: "Year")
        }
    }

    struct Window {
        let start: Date
        let end: Date
        /// The bar's label ("Oct").
        let label: String
        /// The heading over that window's transactions ("October 2026").
        let title: String
    }

    /// Oldest first, ending with the window that contains `now`.
    func windows(now: Date = .now, calendar: Calendar = .current) -> [Window] {
        switch self {
        case .daily:
            let today = calendar.startOfDay(for: now)
            return (0..<7).reversed().compactMap { offset in
                guard let start = calendar.date(byAdding: .day, value: -offset, to: today),
                      let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
                return Window(
                    start: start, end: end, label: start.formatted(.dateTime.weekday(.abbreviated)),
                    title: start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            }
        case .weekly:
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            return (0..<6).reversed().compactMap { offset in
                guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                      let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
                let last = calendar.date(byAdding: .day, value: -1, to: end) ?? end
                let span = start.formatted(.dateTime.month(.abbreviated).day()) + " – "
                    + last.formatted(.dateTime.month(.abbreviated).day())
                return Window(
                    start: start, end: end, label: start.formatted(.dateTime.month(.abbreviated).day()), title: span)
            }
        case .monthly, .year:
            let count = self == .monthly ? 6 : 12
            let thisMonth = LedgerDate.monthStart(of: now, calendar: calendar)
            return (0..<count).reversed().compactMap { offset in
                let start = LedgerDate.adding(months: -offset, to: thisMonth, calendar: calendar)
                let end = LedgerDate.adding(months: 1, to: start, calendar: calendar)
                return Window(
                    start: start, end: end, label: start.formatted(.dateTime.month(.abbreviated)),
                    title: start.formatted(.dateTime.month(.wide).year()))
            }
        }
    }
}

/// Income and expense in dollars over one window.
struct AnalysisBucket: Identifiable, Sendable {
    let id: Int
    let label: String
    var income: Double
    var expense: Double

    /// Sums `rows` (USD, transfers left out) into the windows, in order.
    static func fill(_ windows: [AnalysisRange.Window], from rows: [LedgerTransaction]) -> [AnalysisBucket] {
        var buckets = windows.enumerated().map { AnalysisBucket(id: $0.offset, label: $0.element.label, income: 0, expense: 0) }
        for row in rows {
            guard let date = row.date,
                  let index = windows.firstIndex(where: { date >= $0.start && date < $0.end }) else { continue }
            switch row.direction {
            case .income: buckets[index].income += Double(row.baseCents) / 100
            case .expense: buckets[index].expense += Double(row.baseCents) / 100
            case .transferIn, .transferOut: break
            }
        }
        return buckets
    }
}
