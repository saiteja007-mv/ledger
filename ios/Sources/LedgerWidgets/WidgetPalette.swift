import SwiftUI
import UIKit
import WidgetKit

/// The app's Finance-kit palette (`KitColor`), repeated here because the extension is its own module.
enum WidgetPalette {
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        func ui(_ value: UInt32) -> UIColor {
            UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    /// The yellow hero card.
    static let hero = adaptive(light: 0xFDFF96, dark: 0xFCFF76)
    static let background = adaptive(light: 0xFFFFFF, dark: 0x000000)
    static let surface = adaptive(light: 0xF2F2F2, dark: 0x191A1D)
    static let label = adaptive(light: 0x000000, dark: 0xFFFFFF)
    static let secondary = adaptive(light: 0x575757, dark: 0xA0A0A0)
    static let accent = adaptive(light: 0x365FF1, dark: 0x4D72F5)
    static let positive = Color(red: 0x4A / 255, green: 0xA8 / 255, blue: 0x79 / 255)
    static let warning = Color(red: 0xF8 / 255, green: 0xA7 / 255, blue: 0x2E / 255)
    static let destructive = Color(red: 0xEB / 255, green: 0x6C / 255, blue: 0x86 / 255)

    static func tint(for budget: WidgetBudget) -> Color {
        switch budget.status {
        case "over": destructive
        case "warning": warning
        default: accent
        }
    }
}

/// A rounded progress line: the kit's "Monthly payment limit".
struct WidgetBar: View {
    let fraction: Double
    var tint: Color = WidgetPalette.accent
    var track: Color = WidgetPalette.surface

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: max(proxy.size.height, proxy.size.width * fraction))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// What every widget draws when the ledger can't be read: never stale numbers.
struct WidgetUnavailable: View {
    let date: Date

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "wifi.exclamationmark").font(.title3)
            Text("Ledger unreachable").font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            Text("Tailscale off?").font(.caption2)
            Text(date, style: .time).font(.caption2)
        }
        .foregroundStyle(WidgetPalette.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
