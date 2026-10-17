import SwiftUI

/// One category's expenses over a month: what a budget row, a chart arc or a category row adds up. Drawn as
/// the kit's transaction page: the avatar, the name, the month, the total, then the rows. The total and
/// the rows are the same set the ledger sums, so they always agree.
struct CategoryDetailView: View {
    let scope: CategoryScope

    @Environment(LedgerStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var editing: BudgetEdit?

    private var cache: CategoryTransactionsCache { store.categoryTransactions }

    /// The budget that limits exactly this scope, if one is set.
    private var budget: BudgetStatus? {
        store.budgets.value?.first { $0.category == (scope.category ?? CategoryScope.total) }
    }

    private var list: TransactionList? { cache.entries[scope]?.value }

    var body: some View {
        KitScreen(showsBack: true, hero: { hero }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let budget {
                        BudgetRow(budget: budget)
                            .kitCard()
                    }
                    rows
                    actions
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .refreshable { await cache.load(scope, force: true) }
        }
        .sheet(item: $editing, content: SetBudgetView.init)
        // Loads on arrival, again if a write threw the cache away, and is cancelled on leaving.
        .task(id: cache.generation) {
            await cache.load(scope)
        }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            if scope.category != nil {
                KitAvatar(category: scope.title, size: 72)
            } else {
                KitCoin(size: 72)
            }
            Text(scope.title).font(.kitBodyMedium)
            Text(scope.period.title())
                .font(.kitSmallMedium)
                .foregroundStyle(KitColor.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(KitColor.label.color.opacity(0.9), in: .capsule)
                .environment(\.colorScheme, .dark)
            Text(list.map { "^[\($0.rows.count) purchase](inflect: true)" } ?? "")
                .font(.kitSmall)
                .foregroundStyle(KitColor.secondary.color)
            KitAmountView(cents: list?.totalCents ?? 0, size: .hero, isNegative: true)
                .padding(.top, 6)
                .padding(.bottom, 28)
        }
        .foregroundStyle(KitColor.label.color)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var rows: some View {
        switch cache.entries[scope] {
        case .none, .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading transactions…").font(.kitSmall).foregroundStyle(KitColor.secondary.color)
            }
        case .failed(let error):
            InlineError(error: error)
            Button("Try Again", systemImage: "arrow.clockwise") { Task { await cache.load(scope, force: true) } }
        case .loaded(let list) where list.rows.isEmpty:
            Text(emptyText).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
        case .loaded(let list):
            VStack(spacing: 18) {
                ForEach(list.rows) { transaction in
                    NavigationLink(value: Route.transaction(transaction)) {
                        KitTransactionRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                }
            }
            if list.isTruncated {
                Label("There are more in this period than the newest \(list.rows.count.formatted()) shown, so the total is partial.",
                      systemImage: "exclamationmark.triangle")
                    .font(.kitSmall)
                    .foregroundStyle(KitColor.warning.color)
            }
        }
    }

    private var emptyText: String {
        scope.period.isCurrent()
            ? String(localized: "No transactions in \(scope.title) this month")
            : String(localized: "No transactions in \(scope.title) in \(scope.period.title())")
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 4) {
            Button { navigator.showActivity(scope.activityFilter()) } label: {
                KitMenuRow(icon: .payment, title: "Show All in Payments")
            }
            .buttonStyle(.plain)
            if let budget {
                Button {
                    editing = BudgetEdit(category: budget.category, period: budget.period, limitCents: budget.limitCents)
                } label: {
                    KitMenuRow(icon: .edit, title: "Edit Budget")
                }
                .buttonStyle(.plain)
            }
            if budget?.isWeekly == true {
                Text("This is a weekly budget, but Ledger counts it against the whole month's spending, so this list is the month's.")
                    .font(.kitSmall)
                    .foregroundStyle(KitColor.secondary.color)
                    .padding(.top, 8)
            }
        }
    }
}
