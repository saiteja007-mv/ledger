import SwiftUI

/// Payments (Activity): an underlined search with the filter beside it, the income and expense of what's
/// shown, and every row by month, newest first. "Show all in Transactions" elsewhere sets the filter
/// through `Navigator`.
struct TransactionsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var rows: Loadable<TransactionList> = .loading

    var body: some View {
        @Bindable var navigator = navigator
        NavigationStack {
            KitScreen(
                String(localized: "Payments"),
                trailing: { KitBarButton(icon: .plus, label: "Log Spending") { navigator.isAdding = true } }
            ) {
                VStack(spacing: 0) {
                    searchRow(query: $navigator.activityFilter.query)
                    list
                }
            }
            .ledgerDestinations()
            .task(id: navigator.activityFilter) {
                await filterChanged()
            }
            .onChange(of: store.revision) {
                reloadAfterWrite()
            }
        }
    }

    // MARK: Search

    private func searchRow(query: Binding<String>) -> some View {
        HStack(spacing: 8) {
            TextField("Enter merchant, note or category", text: query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .kitUnderlinedField()
            TransactionFilterMenu(
                filter: Bindable(navigator).activityFilter, accounts: store.accounts, categories: store.categories
            )
        }
        .padding(.horizontal, KitMetrics.margin)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    // MARK: List

    private var income: Int {
        rows.value?.rows.filter { $0.direction == .income }.reduce(0) { $0 + $1.baseCents } ?? 0
    }

    private var expense: Int {
        rows.value?.rows.filter { $0.direction == .expense }.reduce(0) { $0 + $1.baseCents } ?? 0
    }

    @ViewBuilder
    private var list: some View {
        switch rows {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ErrorStateView(error: error, retry: load)
        case .loaded(let list):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    HStack {
                        figure(title: "Income", text: "+ " + Money.text(income), color: KitColor.positive.color)
                        Spacer()
                        figure(title: "Expense", text: "- " + Money.text(expense), color: KitColor.label.color)
                    }
                    if list.rows.isEmpty {
                        empty
                    }
                    ForEach(months(of: list.rows), id: \.month) { section in
                        KitSectionLabel(text: section.title).padding(.top, 10)
                        ForEach(section.rows) { transaction in
                            NavigationLink(value: Route.transaction(transaction)) {
                                KitTransactionRow(transaction: transaction)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if list.isTruncated {
                        Label("Showing the newest \(list.rows.count.formatted()) only. Narrow the filters to see older ones.",
                              systemImage: "exclamationmark.triangle")
                            .font(.kitSmall)
                            .foregroundStyle(KitColor.warning.color)
                    }
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.bottom, 24)
            }
            .refreshable { await load() }
        }
    }

    private func figure(title: LocalizedStringKey, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
            Text(text).font(.kit(.medium, 18, relativeTo: .headline)).foregroundStyle(color).lineLimit(1)
        }
    }

    @ViewBuilder
    private var empty: some View {
        if navigator.activityFilter.trimmedQuery.isEmpty {
            ContentUnavailableView("No Transactions", systemImage: "tray", description: Text("Nothing matches these filters."))
        } else {
            ContentUnavailableView.search
        }
    }

    /// Rows are newest first, so a month's rows are contiguous.
    private func months(of rows: [LedgerTransaction]) -> [(month: String, title: String, rows: [LedgerTransaction])] {
        var result: [(month: String, title: String, rows: [LedgerTransaction])] = []
        for row in rows {
            let month = String(row.postedAt.prefix(7))
            if result.last?.month == month {
                result[result.count - 1].rows.append(row)
            } else {
                result.append((month, monthTitle(month), [row]))
            }
        }
        return result
    }

    private func monthTitle(_ month: String) -> String {
        guard let period = CategoryPeriod(month: month), let date = LedgerDate.parse(period.from) else { return month }
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.month(.wide)) : date.formatted(.dateTime.month(.wide).year())
    }

    // MARK: Loading

    private func reloadAfterWrite() {
        Task { await load() }
    }

    private func filterChanged() async {
        // Debounce typing; a filter change applies at once.
        if !navigator.activityFilter.trimmedQuery.isEmpty {
            try? await Task.sleep(for: .milliseconds(350))
        }
        guard !Task.isCancelled else { return }
        await load()
    }

    private func load() async {
        let filter = navigator.activityFilter
        let result = await Loadable.capture { try await LedgerAPI.transactions(matching: filter) }
        guard !Task.isCancelled else { return }
        rows = result
    }
}
