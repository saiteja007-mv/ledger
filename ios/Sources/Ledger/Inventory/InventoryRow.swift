import SwiftUI

/// An item as a card: its initial, name and what is left; how many days that is and how long a purchase
/// lasts; a bar of how much is used; and a Used up button while the item is in use. The top of the card opens the item.
struct InventoryRow: View {
    let item: InventoryItem
    let markUsedUp: (InventoryItem) -> Void

    @ScaledMetric private var avatarSize = 42

    private var tint: Color { item.section.tint }

    private var initial: String {
        item.name.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: Route.inventoryItem(item)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(initial)
                            .font(.kit(.medium, 17))
                            .frame(width: avatarSize, height: avatarSize)
                            .background(tint.opacity(0.18), in: .circle)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName).font(.kitBodyMedium).lineLimit(2)
                            Text(item.subtitle).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            if let daysLeft = item.daysLeftText {
                                Text(daysLeft).font(.kitSmallMedium)
                            }
                            if let lasts = item.lastsText {
                                Text(lasts).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
                            }
                        }
                        .multilineTextAlignment(.trailing)
                    }
                    if item.hasEstimate {
                        KitMeter(fraction: item.usedFraction, tint: tint)
                    }
                }
                .foregroundStyle(KitColor.label.color)
                .contentShape(.rect)
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)

            if item.canMarkUsedUp {
                Button(action: usedUpTapped) {
                    Text("Used up")
                        .font(.kitSmallMedium)
                        .foregroundStyle(KitColor.label.color)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(tint.opacity(0.18), in: .capsule)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("Mark \(item.displayName) used up")
                .accessibilityInputLabels(["Used up"])
            }
        }
        .kitCard(padding: 14)
    }

    private func usedUpTapped() {
        markUsedUp(item)
    }
}
