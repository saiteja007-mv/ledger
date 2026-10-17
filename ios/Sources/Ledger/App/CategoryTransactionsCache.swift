import Observation

/// The rows behind each category total, loaded when its row is expanded and kept, so collapsing
/// and expanding again doesn't ask the server again. Any write throws the lot away (`invalidate()`),
/// because it can change any total.
@MainActor
@Observable
final class CategoryTransactionsCache {
    private(set) var entries: [CategoryScope: Loadable<TransactionList>] = [:]
    /// Bumped by `invalidate()`; an expanded row loads again when it changes.
    private(set) var generation = 0
    /// The newest request per scope: an older answer arriving late is dropped.
    @ObservationIgnored private var latest: [CategoryScope: Int] = [:]
    @ObservationIgnored private var requests = 0

    func invalidate() {
        entries = [:]
        generation += 1
    }

    /// Loads `scope` unless it's already loaded. Pass `force` to try a failed one again.
    func load(_ scope: CategoryScope, force: Bool = false) async {
        if !force, case .loaded = entries[scope] { return }
        requests += 1
        let request = requests
        latest[scope] = request
        entries[scope] = .loading

        let result = await Loadable.capture { try await LedgerAPI.categoryTransactions(scope) }
        guard latest[scope] == request else { return }
        // Cancelled by collapsing or leaving the screen: forget the placeholder, don't cache a failure.
        guard !Task.isCancelled else {
            entries[scope] = nil
            return
        }
        entries[scope] = result
    }
}
