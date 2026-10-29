import SwiftUI

/// Under the list: who last updated it ("Updated by Claude 2 h ago", "Rules only", "Updating…") and the
/// Update now button, which only queues a pass: the button waits while one is queued or running.
struct ShoppingUpdateBar: View {
    let ai: ShoppingList.AIStatus
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(ai.footer())
                .font(.kitSmall)
                .foregroundStyle(KitColor.secondary.color)
                .multilineTextAlignment(.center)
            Button(action: refresh) {
                Text("Update now").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(ai.pending)
        }
        .padding(.horizontal, KitMetrics.margin)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(KitColor.background.color)
    }
}
