import SwiftUI

/// Puts `LockView` over a view while locked or inactive. Applied to the root and to every sheet,
/// because a presented sheet sits above the root's overlay.
struct LockCover: ViewModifier {
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let isCovered = !lock.isUnlocked || scenePhase != .active
        content
            .accessibilityHidden(isCovered)
            .overlay {
                if isCovered {
                    LockView(lock: lock)
                }
            }
    }
}

extension View {
    func lockCover() -> some View {
        modifier(LockCover())
    }
}
