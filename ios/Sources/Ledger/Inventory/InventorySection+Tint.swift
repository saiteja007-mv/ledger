import SwiftUI

extension InventorySection {
    /// The section's colour for its icon disc and usage bar: amber running low, red used up. Never the only cue, the text says it too.
    var tint: Color {
        switch self {
        case .runningLow: KitColor.warning.color
        case .inStock: KitColor.positive.color
        case .usedUp: KitColor.destructive.color
        case .learning: KitColor.accent.color
        case .notTracked: KitColor.secondary.color
        }
    }
}
