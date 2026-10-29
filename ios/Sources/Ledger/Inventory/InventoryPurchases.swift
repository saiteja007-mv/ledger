import SwiftUI

/// The price per unit over time and every purchase, with Item Prices' chart and rows.
struct InventoryPurchases: View {
    let points: [PricePoint]
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Price per \(unit)").font(.kitSubtitle)
                PriceChart(points: points, unit: unit)
            }
            .padding(16)
            .background(KitColor.surface.color, in: RoundedRectangle(cornerRadius: 22))

            VStack(alignment: .leading, spacing: 14) {
                Text("Purchases").font(.kitSubtitle)
                ForEach(points.reversed()) { point in
                    PricePointRow(point: point, unit: unit)
                }
            }
        }
    }
}
