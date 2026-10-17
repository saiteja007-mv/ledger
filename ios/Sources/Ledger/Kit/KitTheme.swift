import CoreText
import SwiftUI
import UIKit

/// The Finance Mobile App UI Kit's palette, with a light and a dark value from its Light and Dark flows.
struct KitColor: Sendable {
    let light: UInt32
    let dark: UInt32

    func resolved(for scheme: ColorScheme) -> Color {
        Color(kitRGB: scheme == .dark ? dark : light)
    }

    /// An adaptive colour for use anywhere a `Color` is taken.
    var color: Color {
        Color(UIColor { traits in
            UIColor(kitRGB: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    // Surfaces.
    static let background = KitColor(light: 0xFFFFFF, dark: 0x000000)
    /// The kit's Neutral/200: tracks, chips, quiet cards.
    static let surface = KitColor(light: 0xF2F2F2, dark: 0x191A1D)
    /// The pale-blue header behind a transaction or the account.
    static let tint = KitColor(light: 0xEAEEFF, dark: 0x000000)
    /// Primary/200: an icon circle, a soft highlight.
    static let tintStrong = KitColor(light: 0xDEE5FF, dark: 0x242428)
    /// Secondary/400: the yellow hero card, the active tab.
    static let hero = KitColor(light: 0xFDFF96, dark: 0xFCFF76)
    // Blues.
    static let accent = KitColor(light: 0x4D72F5, dark: 0x365FF1)
    static let accentStrong = KitColor(light: 0x365FF1, dark: 0x004EE4)
    static let accentSoft = KitColor(light: 0xEAEEFF, dark: 0x191A1D)
    // Text.
    static let label = KitColor(light: 0x000000, dark: 0xFFFFFF)
    static let secondary = KitColor(light: 0x575757, dark: 0xA0A0A0)
    static let separator = KitColor(light: 0xDADADA, dark: 0x2A2A2E)
    // Status.
    static let positive = KitColor(light: 0x4AA879, dark: 0x4AA879)
    static let warning = KitColor(light: 0xF8A72E, dark: 0xF8A72E)
    static let destructive = KitColor(light: 0xEB6C86, dark: 0xEB6C86)

    static let yellow = Color(kitRGB: 0xFCFF76)
    static let black = Color(kitRGB: 0x000000)
    static let white = Color(kitRGB: 0xFFFFFF)
}

extension Color {
    init(kitRGB value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    init(kitHex text: String) {
        let digits = text.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(kitRGB: UInt32(digits, radix: 16) ?? 0)
    }
}

extension UIColor {
    convenience init(kitRGB value: UInt32) {
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1
        )
    }
}

/// e-Ukraine, the kit's typeface, bundled in `Resources/Fonts` (CC BY 4.0, The Ministry and the Committee for
/// Digital Transformation of Ukraine: credited under More).
enum KitFont {
    enum Weight: String {
        case light = "e-Ukraine-Light"
        case regular = "e-Ukraine-Regular"
        case medium = "e-Ukraine-Medium"
    }

    /// Registers the bundled OTFs once at launch. Without them `Font.kit` falls back to the system font.
    static func register() {
        let urls = Bundle.module.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? []
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

extension Font {
    /// The kit's e-Ukraine, scaling with Dynamic Type relative to `style`.
    static func kit(_ weight: KitFont.Weight, _ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    // The kit's type scale: Heading XL, Text M/S/XS in medium and regular.
    static let kitHeadingXL = Font.kit(.medium, 56, relativeTo: .largeTitle)
    static let kitHeading = Font.kit(.medium, 24, relativeTo: .title2)
    static let kitTitle = Font.kit(.medium, 20, relativeTo: .title3)
    static let kitSubtitle = Font.kit(.medium, 18, relativeTo: .headline)
    static let kitBodyMedium = Font.kit(.medium, 16, relativeTo: .body)
    static let kitBody = Font.kit(.regular, 16, relativeTo: .body)
    static let kitSmallMedium = Font.kit(.medium, 14, relativeTo: .subheadline)
    static let kitSmall = Font.kit(.regular, 14, relativeTo: .subheadline)
    static let kitCaption = Font.kit(.regular, 12, relativeTo: .caption)
    static let kitCaptionLight = Font.kit(.light, 12, relativeTo: .caption)
}
