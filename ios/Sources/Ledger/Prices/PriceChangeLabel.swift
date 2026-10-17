import SwiftUI

/// A pill: "▲ 12%" on red when a price went up, "▼ 5%" on green when it went down.
struct PriceChangeLabel: View {
    let changePct: Double

    private var isUp: Bool { changePct > 0 }

    private var amount: String {
        (abs(changePct) / 100).formatted(.percent.precision(.fractionLength(0...1)))
    }

    private var tint: Color { isUp ? KitColor.destructive.color : KitColor.positive.color }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8))
            Text(amount).monospacedDigit()
        }
        .font(.kitCaption)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUp ? Text("Up \(amount)") : Text("Down \(amount)"))
    }
}
