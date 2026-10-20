import SwiftUI

/// Account, in the place of the kit's "My account": the pale header with the swirl and a round badge, then
/// grouped rows for what the tab bar has no room for: Accounts, Review, Receipts, Budgets, Item Prices
/// and the Audit Log, a line on Face ID, and the font credit.
struct MoreView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var status: LedgerStatus?

    var body: some View {
        @Bindable var navigator = navigator
        NavigationStack(path: $navigator.morePath) {
            KitScreen(String(localized: "My account"), hero: { badge }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        KitSectionLabel(text: String(localized: "Ledger"))
                            .padding(.bottom, 8)
                        link(.accounts, icon: .card, title: "Accounts",
                             subtitle: String(localized: "Balances, record a balance, reconcile"))
                        link(.review, icon: .checkmark, title: "Review",
                             subtitle: String(localized: "Confirm what assistants and bank alerts wrote"), badge: store.reviewCount)
                        link(.receipts, icon: .invoice, title: "Receipts",
                             subtitle: String(localized: "Itemised receipts and their photos"))
                        link(.budgets, icon: .dollar, title: "Budgets",
                             subtitle: String(localized: "Monthly limits by category"))
                        link(.prices, icon: .foodGroceries, title: "Item Prices",
                             subtitle: String(localized: "What you paid for an item over time"))
                        link(.audit, icon: .repeatPayment, title: "Audit Log",
                             subtitle: String(localized: "The latest writes, from any client"))

                        KitSectionLabel(text: String(localized: "Connections"))
                            .padding(.top, 18)
                            .padding(.bottom, 8)
                        link(.mcp, icon: .security, title: "MCP server",
                             subtitle: String(localized: "How Claude and ChatGPT reach your ledger"))
                        link(.shortcuts, icon: .plus, title: "Siri & Shortcuts",
                             subtitle: String(localized: "Log spending from a widget, Siri or an automation"))

                        KitSectionLabel(text: String(localized: "Settings"))
                            .padding(.top, 18)
                            .padding(.bottom, 8)
                        KitMenuRow(
                            icon: .faceId, title: "Face ID & Passcode",
                            subtitle: String(localized: "Ledger locks on launch and when you leave it"), showsChevron: false
                        )
                        link(.server, icon: .security, title: "Server",
                             subtitle: ServerConfig.serverURL?.host() ?? String(localized: "Not connected"))
                        footer
                    }
                    .padding(.horizontal, KitMetrics.margin)
                    .padding(.top, 22)
                    .padding(.bottom, 24)
                }
            }
            .ledgerDestinations()
            .task(id: store.revision) {
                status = await Loadable.capture { try await LedgerAPI.status() }.value
            }
        }
    }

    private func link(_ route: Route, icon: KitIcon, title: LocalizedStringKey, subtitle: String, badge: Int = 0) -> some View {
        NavigationLink(value: route) {
            KitMenuRow(icon: icon, title: title, subtitle: subtitle, badge: badge)
        }
        .buttonStyle(.plain)
    }

    private var badge: some View {
        ZStack {
            Circle().fill(KitColor.background.color)
            KitCoin(size: 56)
        }
        .frame(width: 88, height: 88)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let status {
                Text("^[\(status.transactions) transaction](inflect: true) · ^[\(status.accounts) account](inflect: true) · ^[\(status.receipts) receipt](inflect: true)")
            }
            Text("Typeset in e-Ukraine, © The Ministry and the Committee for Digital Transformation of Ukraine, CC BY 4.0.")
        }
        .font(.kitCaptionLight)
        .foregroundStyle(KitColor.secondary.color)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}
