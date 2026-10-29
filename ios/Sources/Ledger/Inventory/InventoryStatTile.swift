import SwiftUI

/// A small tinted tile: a label over one figure ("Last price" over "$3.49/gal").
struct InventoryStatTile: View {
    let label: String
    let value: String
    var tint: Color = KitColor.accent.color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.kitCaption).foregroundStyle(KitColor.secondary.color)
            Text(value).font(.kit(.medium, 17)).foregroundStyle(KitColor.label.color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
