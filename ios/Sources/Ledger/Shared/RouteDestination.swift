import SwiftUI

/// The screen for a `Route`.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .transaction(let transaction): TransactionDetailView(transaction: transaction)
        case .receipt(let id): ReceiptDetailView(id: id)
        case .account(let account): AccountDetailView(account: account)
        case .budgets: BudgetsView()
        case .prices: PricesView()
        case .priceHistory(let item): PriceHistoryView(item: item)
        case .audit: AuditView()
        case .category(let scope): CategoryDetailView(scope: scope)
        case .accounts: AccountsView()
        case .review: ReviewView()
        case .receipts: ReceiptsView()
        case .mcp: McpView()
        case .shortcuts: ShortcutsView()
        case .server: ConnectView(canCancel: true)
        }
    }
}

extension View {
    /// Registers `Route` once for the enclosing NavigationStack.
    func ledgerDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            RouteDestination(route: route)
        }
    }
}
