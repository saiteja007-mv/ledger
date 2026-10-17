/// The five tabs, in the kit's tab-bar order. Raw values double as deep links: `ledger://activity`.
///
/// The old tab names still open the right screen: `review`, `receipts` and `accounts` live under More now
/// (`AppTab.link(_:)`), and `home` and `activity` kept their names.
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case home
    case analysis
    case activity
    case categories
    case more

    var id: Self { self }

    var title: String {
        switch self {
        case .home: String(localized: "Wallet")
        case .analysis: String(localized: "Statistics")
        case .activity: String(localized: "Payments")
        case .categories: String(localized: "Categories")
        case .more: String(localized: "Account")
        }
    }

    var icon: KitIcon {
        switch self {
        case .home: .wallet
        case .analysis: .statistic
        case .activity: .payment
        case .categories: .categories
        case .more: .account
        }
    }

    /// Where a deep link's host goes: a tab, and for the screens that moved under More, the route to push.
    static func link(_ host: String) -> (tab: AppTab, route: Route?)? {
        switch host {
        case "review": (.more, .review)
        case "receipts": (.more, .receipts)
        case "accounts": (.more, .accounts)
        case "budgets": (.analysis, nil)
        case "wallet": (.home, nil)
        case "statistics": (.analysis, nil)
        case "account": (.more, nil)
        default: AppTab(rawValue: host).map { ($0, nil) }
        }
    }
}
