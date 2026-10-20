import SwiftUI

/// Wallet, as the kit draws it: the yellow hero card (balance, and a row of accounts where the kit has
/// "Send money"), a bar with the calendar and search, a prompt, and the newest transactions.
struct DashboardView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var recent: Loadable<[LedgerTransaction]> = .loading
    @State private var range = HomeRange.monthly
    /// A net worth group's key (banking, cards, cash, people), or nil for all of them.
    @State private var groupKey: String?

    var body: some View {
        NavigationStack {
            KitScreen {
                content
            }
            .ledgerDestinations()
            .task(id: store.revision) {
                await load()
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch store.netWorth {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ErrorStateView(error: error, retry: reload)
        case .loaded(let netWorth):
            ScrollView {
                VStack(spacing: 0) {
                    heroCard(netWorth)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    historyBar
                    if store.reviewCount > 0 {
                        NavigationLink(value: Route.review) {
                            KitBanner(
                                title: String(localized: "Review \(store.reviewCount) transactions"),
                                subtitle: String(localized: "Check what an assistant or a bank alert wrote")
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    transactions
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .refreshable { await reload() }
        }
    }

    // MARK: Hero card

    /// The card's pages: everything together first, then one per group that has accounts. Groups, not
    /// accounts, so the swipe stays five pages long however many accounts there are.
    private func pages(_ netWorth: NetWorth) -> [String?] {
        [nil] + netWorth.groups.filter { !$0.accounts.isEmpty }.map { Optional($0.key) }
    }

    /// The group the card is on, or nil for net worth.
    private var group: NetWorthGroup? {
        groupKey.flatMap { key in store.netWorth.value?.groups.first { $0.key == key } }
    }

    /// Swipe left and right on the balance, or tap a group's name, to move between all accounts and each
    /// group; the accounts row and the list under the card follow the page.
    private func heroCard(_ netWorth: NetWorth) -> some View {
        ZStack(alignment: .topLeading) {
            KitColor.hero.color
            KitSwirl(cut: .card, fill: KitColor.yellow, outline: KitColor.black)
            VStack(spacing: 0) {
                TabView(selection: $groupKey) {
                    ForEach(pages(netWorth), id: \.self) { key in
                        balancePage(netWorth.groups.first { $0.key == key }, netWorth: netWorth).tag(key)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 144)
                .accessibilityElement(children: .contain)
                .accessibilityAdjustableAction { step($0, pages: pages(netWorth)) }

                groupTabs(netWorth)

                Spacer(minLength: 8)
                accountsRow
            }
            .padding(.top, 18)
            .padding(.bottom, 8)
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: KitMetrics.cardRadius, style: .continuous))
        .animation(.snappy, value: groupKey)
    }

    private func balancePage(_ group: NetWorthGroup?, netWorth: NetWorth) -> some View {
        VStack(spacing: 6) {
            Text(group?.label ?? String(localized: "Net worth"))
                .font(.kitBodyMedium)
            KitAmountView(cents: group?.totalCents ?? netWorth.netCents, currency: nil, size: .hero)
                .environment(\.colorScheme, .light)
                .minimumScaleFactor(0.6)
            Group {
                if let group {
                    Text("^[\(group.accounts.count) account](inflect: true)")
                } else {
                    Text("All accounts")
                }
            }
            .font(.kitBody)
            .lineLimit(1)
        }
        .foregroundStyle(KitColor.black)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
    }

    /// The pages' names, in place of dots: the current one is filled, and a tap jumps to any of them.
    private func groupTabs(_ netWorth: NetWorth) -> some View {
        let tabs = HStack(spacing: 4) {
            ForEach(pages(netWorth), id: \.self) { key in
                let selected = key == groupKey
                Button { groupKey = key } label: {
                    Text(netWorth.groups.first { $0.key == key }?.label ?? String(localized: "All"))
                        .font(.kitSmallMedium)
                        .foregroundStyle(selected ? KitColor.yellow : KitColor.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selected ? KitColor.black : .clear, in: .capsule)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        // Scrolls only when the names don't fit, at large text sizes.
        return ViewThatFits(in: .horizontal) {
            tabs
            ScrollView(.horizontal, showsIndicators: false) { tabs.padding(.horizontal, 20) }
        }
        .frame(maxWidth: .infinity)
    }

    private func step(_ direction: AccessibilityAdjustmentDirection, pages: [String?]) {
        guard let index = pages.firstIndex(of: groupKey) else { return }
        switch direction {
        case .increment where index + 1 < pages.count: groupKey = pages[index + 1]
        case .decrement where index > 0: groupKey = pages[index - 1]
        default: break
        }
    }

    /// The kit's "Send money" row: a black action circle, then a circle per account on the card's page,
    /// each with its balance (cards show what you owe).
    private var accountsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                Button { navigator.isAdding = true } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().fill(KitColor.black)
                            KitIconView(icon: .plus, height: 24, color: KitColor.white)
                        }
                        .frame(width: 56, height: 56)
                        Text("Log").font(.kitSmallMedium).foregroundStyle(KitColor.black)
                    }
                }
                .accessibilityLabel("Log Spending")
                ForEach(group?.accounts ?? store.accounts) { account in
                    NavigationLink(value: Route.account(account)) {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(KitCategory(name: account.kindResolved).avatar.background)
                                Text(initials(account.name))
                                    .font(.kit(.medium, 16))
                                    .foregroundStyle(KitColor.white)
                            }
                            .frame(width: 56, height: 56)
                            Text(account.name)
                                .font(.kitSmallMedium)
                                .foregroundStyle(KitColor.black)
                            Text(Money.text(account.currentCents, currency: account.currency))
                                .font(.kitSmall)
                                .monospacedDigit()
                                .foregroundStyle(KitColor.black.opacity(0.7))
                                .minimumScaleFactor(0.7)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: 72)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 14)
    }

    private func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    // MARK: History

    /// Calendar (the window), the window's name, search.
    private var historyBar: some View {
        HStack {
            Menu {
                Picker("Show", selection: $range) {
                    ForEach(HomeRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
            } label: {
                KitIconView(icon: .calendar, height: 24, color: KitColor.label.color)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Period")
            Spacer()
            Text(range.title).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
            Spacer()
            KitBarButton(icon: .search, label: "Search") { navigator.tab = .activity }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var transactions: some View {
        switch recent {
        case .loading:
            ProgressView().padding(.top, 20)
        case .failed(let error):
            InlineError(error: error)
        case .loaded(let all):
            let shown = all.filter { range.includes($0) && onPage($0) }
            if shown.isEmpty {
                Text(all.isEmpty ? "Nothing logged yet." : "Nothing \(range.phrase).")
                    .font(.kitSmall)
                    .foregroundStyle(KitColor.secondary.color)
                    .padding(.top, 12)
            } else {
                VStack(spacing: 18) {
                    ForEach(shown) { transaction in
                        NavigationLink(value: Route.transaction(transaction)) {
                            KitTransactionRow(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("See all transactions") { navigator.tab = .activity }
                        .font(.kitSmallMedium)
                        .foregroundStyle(KitColor.accent.color)
                }
                .padding(.top, 8)
            }
        }
    }

    /// Whether a row belongs to an account on the card's page.
    private func onPage(_ transaction: LedgerTransaction) -> Bool {
        group?.accounts.contains { $0.name == transaction.account } ?? true
    }

    // MARK: Loading

    private func reload() async {
        store.categoryTransactions.invalidate()
        async let shared: Void = store.refresh()
        async let own: Void = load()
        _ = await (shared, own)
    }

    private func load() async {
        let result = await Loadable.capture { try await LedgerAPI.recentTransactions(limit: 100) }
        guard !Task.isCancelled else { return }
        recent = result
    }
}

/// The three windows the calendar button offers on the wallet.
enum HomeRange: CaseIterable, Hashable {
    case daily, weekly, monthly

    var title: String {
        switch self {
        case .daily: String(localized: "Today")
        case .weekly: String(localized: "This week")
        case .monthly: String(localized: "This month")
        }
    }

    var phrase: String {
        switch self {
        case .daily: String(localized: "today")
        case .weekly: String(localized: "in the last 7 days")
        case .monthly: String(localized: "this month")
        }
    }

    func includes(_ transaction: LedgerTransaction, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let date = transaction.date else { return false }
        switch self {
        case .daily: return calendar.isDate(date, inSameDayAs: now)
        case .weekly: return date >= (calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now)
        case .monthly: return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }
    }
}
