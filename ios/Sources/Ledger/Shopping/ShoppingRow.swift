import SwiftUI

/// One thing to buy: a tick that marks it bought, its name and quantity, why it is on the list, and what it
/// last cost and where it is cheapest. Swiping dismisses or removes it (the list view adds those).
struct ShoppingRow: View {
    let item: ShoppingItem
    let markBought: (ShoppingItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(action: boughtTapped) {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(KitColor.secondary.color)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(item.displayName) bought")
            .accessibilityInputLabels(["Bought"])

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.displayName).font(.kitBodyMedium)
                    Spacer(minLength: 8)
                    if let qty = item.qtyText {
                        Text(qty).font(.kitBodyMedium).monospacedDigit().foregroundStyle(KitColor.secondary.color)
                    }
                }
                if let reason = item.reasonText {
                    Text(reason).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
                }
                if let hint = item.priceHint {
                    Text(hint).font(.kitSmall).monospacedDigit().foregroundStyle(KitColor.secondary.color)
                }
            }
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
        .foregroundStyle(KitColor.label.color)
    }

    private func boughtTapped() {
        markBought(item)
    }
}
