import SwiftUI

/// Categories: every category the ledger has as a kit row (icon, name, this month's spend, a chevron), the
/// busiest first. A row opens that category's expenses for the month.
struct CategoriesView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(Navigator.self) private var navigator

    var body: some View {
        NavigationStack {
            KitScreen(
                String(localized: "Categories"),
                trailing: { KitBarButton(icon: .plus, label: "Log Spending") { navigator.isAdding = true } }
            ) {
                content
            }
            .ledgerDestinations()
        }
    }

    /// This month's categories by spend, then the rest of the ledger's categories A to Z. Account names and
    /// bookkeeping labels (which transfers carry) aren't categories, and each name shows once.
    private var tiles: [(name: String, cents: Int?)] {
        let accounts = Set(store.accounts.map(\.name))
        let spent = store.breakdown.value ?? []
        let seen = Set(spent.map { CategoryName.display($0.category).lowercased() })
        let rest = CategoryName.unique(store.categories)
            .filter { CategoryName.isSpendingCategory($0, accountNames: accounts) }
            .filter { !seen.contains(CategoryName.display($0).lowercased()) }
            .sorted { CategoryName.display($0).localizedStandardCompare(CategoryName.display($1)) == .orderedAscending }
        return spent.map { ($0.category, $0.totalCents) } + rest.map { ($0, nil) }
    }

    @ViewBuilder
    private var content: some View {
        switch store.breakdown {
        case .loading where store.categories.isEmpty:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error) where store.categories.isEmpty:
            ErrorStateView(error: error) { await store.refresh() }
        default:
            ScrollView {
                VStack(spacing: 0) {
                    if let summary = store.summary.value {
                        VStack(spacing: 2) {
                            KitAmountView(cents: summary.expenseCents, size: .medium)
                            Text("Total spent for \(store.period.title())")
                                .font(.kitSmall)
                                .foregroundStyle(KitColor.secondary.color)
                        }
                        .padding(.top, 14)
                        .padding(.bottom, 18)
                    }
                    if tiles.isEmpty {
                        ContentUnavailableView("No Categories", systemImage: "square.grid.2x2",
                                               description: Text("Categories appear as you log spending."))
                            .padding(.top, 40)
                    }
                    LazyVStack(spacing: 20) {
                        ForEach(tiles, id: \.name) { tile in
                            NavigationLink(value: Route.category(CategoryScope(name: tile.name, period: store.period))) {
                                HStack(spacing: 16) {
                                    KitAvatar(category: tile.name)
                                    Text(CategoryName.display(tile.name))
                                        .font(.kitBodyMedium)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    if let cents = tile.cents {
                                        Text("- " + Money.text(cents))
                                            .font(.kitBodyMedium)
                                            .monospacedDigit()
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 13))
                                }
                                .foregroundStyle(KitColor.label.color)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, KitMetrics.margin)
                    .padding(.bottom, 24)
                }
            }
            .refreshable { await store.refresh() }
        }
    }
}
