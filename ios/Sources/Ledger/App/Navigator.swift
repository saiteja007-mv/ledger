import Observation

/// Which tab is up, what Activity is filtered to, and what More has pushed, so any screen can send you to a
/// filtered Activity ("Show all in Activity") and deep links can pick a tab or a screen under More.
@MainActor
@Observable
final class Navigator {
    var tab = AppTab.home
    var activityFilter = TransactionFilter()
    /// More's stack, so a deep link or a new receipt can push onto it from outside.
    var morePath: [Route] = []
    /// Log Spending is up.
    var isAdding = false
    /// What a Siri / Shortcuts link filled in for the next Log Spending; cleared when the form closes.
    var addPrefill: NewTransaction?

    func showActivity(_ filter: TransactionFilter) {
        activityFilter = filter
        tab = .activity
    }

    func show(_ route: Route) {
        tab = .more
        morePath = [route]
    }
}
