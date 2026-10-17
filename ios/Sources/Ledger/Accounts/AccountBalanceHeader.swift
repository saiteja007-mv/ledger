import SwiftUI

/// The balance as of now, and how it's made: the latest reported balance plus movement since.
struct AccountBalanceHeader: View {
    let account: AccountBalance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(account.isLiability ? "Owed now" : "Balance now")
                .font(.kit(.regular, 14, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
            Text(Money.text(account.currentCents, currency: account.currency))
                .font(.kit(.medium, 30, relativeTo: .largeTitle))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let anchor = account.latestBalance {
                Text("\(Money.text(anchor.cents, currency: account.currency)) reported \(LedgerDate.display(anchor.asOfDate)), \(Money.text(account.driftCents ?? 0, currency: account.currency)) since")
                    .font(.kit(.regular, 14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            } else {
                Text("No reported balance yet, so this is the sum of its ^[\(account.transactions) transaction](inflect: true).")
                    .font(.kit(.regular, 14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
