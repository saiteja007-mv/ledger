import SwiftUI

/// The buttons on an item's screen: Used up while it's in use, and Track or Don't track as the item allows.
struct InventoryItemActions: View {
    let item: InventoryItem
    let usedUp: () -> Void
    let track: () -> Void
    let stopTracking: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if item.canMarkUsedUp {
                Button("Used up", action: usedUp)
                    .buttonStyle(KitPrimaryButtonStyle())
            }
            if item.canTrack {
                Button(action: track) {
                    Text("Track").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
            if item.canStopTracking {
                Button(action: stopTracking) {
                    Text("Don't track").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
        }
    }
}
