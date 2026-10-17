import SwiftUI

/// The big amount, the merchant and when.
struct TransactionHeader: View {
    let transaction: LedgerTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(transaction.direction.label)
            } icon: {
                Image(systemName: transaction.direction.systemImage)
            }
            .font(.kit(.regular, 14, relativeTo: .subheadline))
            .foregroundStyle(.secondary)
            AmountText(cents: transaction.amountCents, currency: transaction.currency, direction: transaction.direction)
                .font(.kit(.medium, 30, relativeTo: .largeTitle))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(transaction.title)
                .font(.kit(.medium, 17, relativeTo: .headline))
            Text(LedgerDate.display(transaction.postedAt))
                .font(.kit(.regular, 14, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
