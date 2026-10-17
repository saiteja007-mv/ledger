import SwiftUI

/// Period, type, account and category filters for Payments, behind the kit's filter icon.
struct TransactionFilterMenu: View {
    @Binding var filter: TransactionFilter
    let accounts: [AccountBalance]
    let categories: [String]

    /// The standard periods, plus the specific month a link from a budget or the chart chose.
    private var periods: [TransactionPeriod] {
        if case .month = filter.period {
            TransactionPeriod.standard + [filter.period]
        } else {
            TransactionPeriod.standard
        }
    }

    var body: some View {
        Menu {
            Picker("Period", selection: $filter.period) {
                ForEach(periods) { period in
                    Text(period.label).tag(period)
                }
            }
            Picker("Type", selection: $filter.direction) {
                Text("All types").tag(Direction?.none)
                ForEach(Direction.allCases) { direction in
                    Text(direction.label).tag(Direction?.some(direction))
                }
            }
            Picker("Account", selection: $filter.account) {
                Text("All accounts").tag(String?.none)
                ForEach(accounts) { account in
                    Text(account.name).tag(String?.some(account.name))
                }
            }
            .pickerStyle(.menu)
            Picker("Category", selection: $filter.category) {
                Text("All categories").tag(String?.none)
                Text("Uncategorized").tag(String?.some(CategoryScope.uncategorized))
                ForEach(categories, id: \.self) { category in
                    Text(category).tag(String?.some(category))
                }
            }
            .pickerStyle(.menu)
            if filter.isFiltered {
                Button("Clear Filters", systemImage: "xmark.circle", role: .destructive, action: clear)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                KitIconView(icon: .filter, height: 24, color: KitColor.label.color)
                    .frame(width: 44, height: 44)
                if filter.isFiltered {
                    Circle().fill(KitColor.accent.color).frame(width: 10, height: 10).offset(x: -6, y: 6)
                }
            }
        }
        .accessibilityLabel("Filter")
        .accessibilityValue(filter.isFiltered ? Text("Filtered") : Text("All transactions"))
    }

    private func clear() {
        filter = TransactionFilter(query: filter.query)
    }
}
