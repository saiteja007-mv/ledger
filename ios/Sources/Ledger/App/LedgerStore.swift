import Observation

/// What several screens share: accounts and net worth, this month's totals, budgets and category
/// breakdown, the category list, the review count.
/// After any write a screen calls `didChange()`; screens reload on `revision`.
@MainActor
@Observable
final class LedgerStore {
    private(set) var netWorth: Loadable<NetWorth> = .loading
    private(set) var summary: Loadable<SpendingSummary> = .loading
    private(set) var budgets: Loadable<[BudgetStatus]> = .loading
    /// This month's expense by category, largest first.
    private(set) var breakdown: Loadable<[CategoryTotal]> = .loading
    private(set) var categories: [String] = []
    private(set) var reviewCount = 0
    /// Bumped after every write, so every open screen reloads what it shows.
    private(set) var revision = 0
    /// The rows behind category totals, shared by Home and Budgets.
    let categoryTransactions = CategoryTransactionsCache()

    var accounts: [AccountBalance] {
        netWorth.value?.accounts ?? []
    }

    /// The month the totals above cover; the phone's month stands in until the summary arrives.
    var period: CategoryPeriod {
        summary.value?.period ?? CategoryPeriod(containing: .now)
    }

    func refresh() async {
        async let netWorth = Loadable.capture { try await LedgerAPI.netWorth() }
        async let summary = Loadable.capture { try await LedgerAPI.spendingSummary() }
        async let budgets = Loadable.capture { try await LedgerAPI.budgetStatus() }
        async let breakdown = Loadable.capture { try await LedgerAPI.categoryBreakdown() }
        async let categories = Loadable.capture { try await LedgerAPI.categories() }
        async let queue = Loadable.capture { try await LedgerAPI.reviewQueue() }
        let results = await (netWorth, summary, budgets, breakdown, categories, queue)
        guard !Task.isCancelled else { return }
        self.netWorth = results.0
        self.summary = results.1
        self.budgets = results.2
        self.breakdown = results.3
        // Pickers keep the last good list: a category list going stale for a minute costs nothing.
        if let categories = results.4.value { self.categories = categories }
        if let queue = results.5.value { reviewCount = queue.count }
    }

    func didChange() {
        revision += 1
        categoryTransactions.invalidate()
    }
}
