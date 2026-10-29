import SwiftUI

/// The top of an item's screen: name, what is left and for how long, the usage bar, when and where it was
/// bought cheapest, and three figures (last price, days one unit lasts, cycles the estimate rests on).
struct InventoryItemHeader: View {
    let item: InventoryItem

    private var perUnit: String {
        let unit = Quantity.measuredUnit(item.unit) ?? String(localized: "item")
        return String(localized: "Days per \(unit)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayName).font(.kit(.medium, 24, relativeTo: .title2)).lineLimit(3)
                Text(item.subtitle).font(.kitBody).foregroundStyle(KitColor.secondary.color)
                if item.daysLeftText != nil || item.lastsText != nil {
                    Text([item.daysLeftText, item.lastsText].compactMap { $0 }.joined(separator: " · "))
                        .font(.kitBodyMedium)
                }
                if item.hasEstimate {
                    KitMeter(fraction: item.usedFraction, tint: item.section.tint)
                        .padding(.top, 4)
                }
                if let bought = item.boughtText {
                    Text(bought).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
                }
                if let merchant = item.cheapestMerchant {
                    Text("Cheapest recently at \(merchant)").font(.kitSmall).foregroundStyle(KitColor.secondary.color)
                }
            }
            .foregroundStyle(KitColor.label.color)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                InventoryStatTile(label: String(localized: "Last price"), value: item.priceText ?? "—")
                InventoryStatTile(
                    label: perUnit, value: item.daysPerUnit.map { Quantity.number($0) } ?? "—", tint: item.section.tint)
                InventoryStatTile(label: String(localized: "Cycles"), value: item.cycles.formatted())
            }
        }
    }
}
