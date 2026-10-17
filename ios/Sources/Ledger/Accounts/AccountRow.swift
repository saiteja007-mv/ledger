import SwiftUI

/// An account's name and its balance as of now. Cards show what you owe.
struct AccountRow: View {
    let account: AccountBalance

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                if let anchor = account.latestBalance {
                    Text("Reported \(LedgerDate.display(anchor.asOfDate))")
                        .font(.kit(.regular, 14, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                } else {
                    Label("No reported balance", systemImage: "exclamationmark.circle")
                        .font(.kit(.regular, 14, relativeTo: .subheadline))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.text(account.currentCents, currency: account.currency))
                    .monospacedDigit()
                if account.isLiability {
                    Text("owed")
                        .font(.kit(.regular, 14, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
