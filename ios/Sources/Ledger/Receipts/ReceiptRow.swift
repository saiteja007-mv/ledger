import SwiftUI

/// Merchant, date, total, and whether the photo has been read and attached.
struct ReceiptRow: View {
    let receipt: Receipt

    private var details: String {
        var parts: [String] = []
        if let purchasedAt = receipt.purchasedAt { parts.append(LedgerDate.display(purchasedAt)) }
        if !receipt.items.isEmpty { parts.append(String(localized: "\(receipt.items.count) items")) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.title)
                    .lineLimit(1)
                if !details.isEmpty {
                    Text(details)
                        .font(.kit(.regular, 14, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                }
                BillStatusLabel(receipt: receipt)
            }
            Spacer(minLength: 8)
            if let total = receipt.totalCents {
                Text(Money.text(total, currency: receipt.currency))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
