import SwiftUI

/// Accounts, as the kit's "Your cards": each account is a blue card with its balance and a coin, and the
/// overall monthly limit sits under them like the kit's "Monthly payment limit".
struct AccountsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var status: LedgerStatus?

    var body: some View {
        KitScreen(String(localized: "Your accounts"), showsBack: true) {
            LoadableView(state: store.netWorth, retry: refresh) { netWorth in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(netWorth.groups.filter { !$0.accounts.isEmpty }) { group in
                            HStack {
                                Text(group.label).font(.kitSubtitle)
                                Spacer()
                                Text(Money.text(group.totalCents)).font(.kitSmallMedium).monospacedDigit()
                            }
                            .padding(.top, 6)
                            ForEach(group.accounts) { account in
                                NavigationLink(value: Route.account(account)) {
                                    card(account)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if let total = store.budgets.value?.first(where: \.isTotal) {
                            NavigationLink(value: Route.category(total.scope())) {
                                BudgetRow(budget: total).kitCard()
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                        }
                        if netWorth.unverifiedCount > 0 {
                            Label("^[\(netWorth.unverifiedCount) account](inflect: true) with no reported balance yet", systemImage: "exclamationmark.circle")
                                .font(.kitSmall)
                                .foregroundStyle(KitColor.secondary.color)
                        }
                        AboutFooter(status: status)
                            .font(.kitCaptionLight)
                            .foregroundStyle(KitColor.secondary.color)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .refreshable { await refresh() }
            }
        }
        .task(id: store.revision) {
            await loadStatus()
        }
    }

    /// 343 pt wide, 150 tall: name and kind over the balance, a coin at the corner.
    private func card(_ account: AccountBalance) -> some View {
        ZStack(alignment: .topTrailing) {
            KitColor.accentStrong.color
            KitCoin(size: 64).offset(x: -16, y: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(account.isLiability ? "Credit" : account.kindResolved.capitalized).font(.kitBodyMedium)
                Spacer()
                if let anchor = account.latestBalance {
                    Text("Reported \(LedgerDate.display(anchor.asOfDate))").font(.kitSmall).opacity(0.85)
                } else {
                    Text("No reported balance").font(.kitSmall).opacity(0.85)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(account.name).font(.kit(.medium, 20, relativeTo: .title3)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Money.text(account.currentCents, currency: account.currency))
                        .font(.kit(.medium, 20, relativeTo: .title3))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(KitColor.white)
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func refresh() async {
        await store.refresh()
        await loadStatus()
    }

    private func loadStatus() async {
        status = await Loadable.capture { try await LedgerAPI.status() }.value
    }
}
