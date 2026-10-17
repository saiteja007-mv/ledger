import SwiftUI

/// Merchant, category, account and date on the left; the signed amount on the right.
/// A dashed circle marks a row nobody has reviewed yet.
struct TransactionRow: View {
    let transaction: LedgerTransaction

    private var details: String {
        [transaction.category, transaction.account, transaction.date?.formatted(date: .abbreviated, time: .omitted)]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title)
                    .lineLimit(1)
                Text(details)
                    .font(.kit(.regular, 14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(cents: transaction.amountCents, currency: transaction.currency, direction: transaction.direction)
                if transaction.reviewed == false {
                    Label("Not reviewed", systemImage: "circle.dashed")
                        .labelStyle(.iconOnly)
                        .font(.kit(.regular, 14, relativeTo: .subheadline))
                        .foregroundStyle(.orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
