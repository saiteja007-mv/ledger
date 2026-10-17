import SwiftUI

/// An item as a card: its initial, name and where it was last bought; the latest price per unit with how it
/// moved; and a line from the lowest to the highest price it has cost, marking where the latest sits.
struct PriceRow: View {
    let item: PriceItem

    private static let palette: [UInt32] = [0x16A34A, 0x0891B2, 0xF97316, 0x8B5CF6, 0xE53D60, 0x0D9488, 0xEAB308, 0x365FF1]

    private var tint: Color {
        let index = item.name.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 997 } % Self.palette.count
        return Color(kitRGB: Self.palette[index])
    }

    private var initial: String {
        item.name.first.map { String($0).uppercased() } ?? "?"
    }

    private var subtitle: String {
        let times = String(localized: "Bought \(item.purchases)×")
        return item.lastMerchant.map { "\(times) · \($0)" } ?? times
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(initial)
                    .font(.kit(.medium, 17))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name.capitalized).font(.kitBodyMedium).lineLimit(2)
                    Text(subtitle).font(.kitSmall).foregroundStyle(KitColor.secondary.color).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    if let last = item.lastCents {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(Money.text(last)).font(.kit(.medium, 17)).monospacedDigit()
                            Text("/\(item.unit)").font(.kitCaption).foregroundStyle(KitColor.secondary.color)
                        }
                    }
                    if let change = item.changePct, change != 0 {
                        PriceChangeLabel(changePct: change)
                    }
                }
            }
            if let low = item.minCents, let high = item.maxCents, high > low, let last = item.lastCents {
                PriceRangeBar(low: low, high: high, value: last, tint: tint)
            }
        }
        .padding(14)
        .background(KitColor.surface.color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .foregroundStyle(KitColor.label.color)
        .accessibilityElement(children: .combine)
    }
}

/// Lowest to highest price as a track, with a dot where `value` sits, and the two ends labelled.
struct PriceRangeBar: View {
    let low: Double
    let high: Double
    let value: Double
    var tint: Color = KitColor.accent.color

    private var fraction: Double {
        min(max((value - low) / (high - low), 0), 1)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(KitColor.separator.color).frame(height: 4)
                    Capsule().fill(tint.opacity(0.5)).frame(width: proxy.size.width * fraction, height: 4)
                    Circle()
                        .fill(tint)
                        .overlay(Circle().stroke(KitColor.background.color, lineWidth: 2))
                        .frame(width: 12, height: 12)
                        .offset(x: proxy.size.width * fraction - 6)
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            HStack {
                Text("Low \(Money.text(low))")
                Spacer()
                Text("High \(Money.text(high))")
            }
            .font(.kitCaption)
            .foregroundStyle(KitColor.secondary.color)
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Between \(Money.text(low)) and \(Money.text(high))"))
    }
}
