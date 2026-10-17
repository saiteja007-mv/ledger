import SwiftUI

/// Every budget against this month's spending, worst first, as the kit's monthly limits. Tap one for the
/// expenses behind its number, or its pencil to change the limit.
struct BudgetsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var editing: BudgetEdit?

    var body: some View {
        KitScreen(String(localized: "Budgets"), showsBack: true, trailing: {
            KitBarButton(icon: .plus, label: "New Budget", action: add)
        }) {
            content
        }
        .sheet(item: $editing, content: SetBudgetView.init)
    }

    @ViewBuilder
    private var content: some View {
        switch store.budgets {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ErrorStateView(error: error) { await store.refresh() }
        case .loaded(let budgets):
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if budgets.isEmpty {
                        ContentUnavailableView("No Budgets", systemImage: "gauge.with.dots.needle.33percent",
                                               description: Text("Set a monthly limit for a category, or for everything."))
                    }
                    ForEach(budgets) { budget in
                        HStack(spacing: 8) {
                            NavigationLink(value: Route.category(budget.scope())) {
                                BudgetRow(budget: budget)
                            }
                            .buttonStyle(.plain)
                            KitBarButton(icon: .edit, label: "Edit Budget") { edit(budget) }
                        }
                    }
                    Text("A budget on “Total” limits all spending together.")
                        .font(.kitSmall)
                        .foregroundStyle(KitColor.secondary.color)
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .refreshable {
                store.categoryTransactions.invalidate()
                await store.refresh()
            }
        }
    }

    private func add() {
        editing = BudgetEdit(category: nil, period: "monthly", limitCents: nil)
    }

    private func edit(_ budget: BudgetStatus) {
        editing = BudgetEdit(category: budget.category, period: budget.period, limitCents: budget.limitCents)
    }
}
