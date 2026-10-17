import SwiftUI

/// Covers everything while locked, and while the app isn't active so the app switcher shows no numbers.
/// Drawn as the kit's "Security" entrance: a big heading, a Face ID glyph, a black action.
struct LockView: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(KitColor.hero.color)
                KitIconView(icon: .faceId, height: 64, color: KitColor.black)
            }
            .frame(width: 160, height: 160)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(lock.isUnlocked ? "Ledger" : "Ledger is locked").font(.kitHeading)
                Text("Use Face ID to open your finances.")
                    .font(.kitSmall)
                    .foregroundStyle(KitColor.secondary.color)
                if let error = lock.lastError, !lock.isUnlocked {
                    Text(error)
                        .font(.kitSmall)
                        .foregroundStyle(KitColor.destructive.color)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 32)

            Spacer()
            if !lock.isUnlocked {
                Button("Unlock with Face ID", action: unlock)
                    .buttonStyle(KitPrimaryButtonStyle())
                    .padding(.horizontal, KitMetrics.margin)
                    .padding(.bottom, 24)
            }
        }
        .foregroundStyle(KitColor.label.color)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KitColor.background.color.ignoresSafeArea())
    }

    private func unlock() {
        Task { await lock.unlock() }
    }
}
