import SwiftUI

/// One purchase: the store (its logo when known), when and how much, and the unit price.
struct PricePointRow: View {
    let point: PricePoint
    let unit: String

    var body: some View {
        HStack(spacing: 12) {
            KitAvatar(category: "Groceries", merchant: point.merchant, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(point.merchant ?? String(localized: "Unknown store")).font(.kitBodyMedium).lineLimit(1)
                Text("\(point.purchasedAt.map(LedgerDate.display) ?? "—") · \(point.qty.formatted()) \(point.unit)")
                    .font(.kitSmall)
                    .foregroundStyle(KitColor.secondary.color)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.text(point.totalCents)).font(.kitBodyMedium).monospacedDigit()
                if let unitPrice = point.unitPriceCents {
                    Text("\(Money.text(unitPrice))/\(unit)")
                        .font(.kitSmall)
                        .monospacedDigit()
                        .foregroundStyle(KitColor.secondary.color)
                }
            }
        }
        .foregroundStyle(KitColor.label.color)
        .accessibilityElement(children: .combine)
    }
}
