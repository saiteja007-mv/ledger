import LocalAuthentication
import Observation
import SwiftUI

/// Face ID (or the passcode) on launch and on every return from the background.
@MainActor
@Observable
final class AppLock {
    private(set) var isUnlocked = false
    private(set) var lastError: String?
    /// Prompt automatically only on launch and on coming back from the background. Not on every
    /// `.active`: the Face ID sheet itself makes the scene inactive, so that would loop after a cancel.
    @ObservationIgnored private var promptWhenActive = true
    @ObservationIgnored private var isPrompting = false

    func scenePhaseChanged(to phase: ScenePhase) async {
        switch phase {
        case .background:
            isUnlocked = false
            promptWhenActive = true
        case .active where promptWhenActive && !isUnlocked:
            promptWhenActive = false
            await unlock()
        default:
            break
        }
    }

    func unlock() async {
        guard !isPrompting else { return }
        isPrompting = true
        defer { isPrompting = false }

        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Not Now")
        var error: NSError?
        // Falls back to the passcode when Face ID isn't set up or fails repeatedly.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = error?.localizedDescription ?? String(localized: "Face ID isn't available")
            return
        }
        do {
            isUnlocked = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock Ledger"))
            lastError = nil
        } catch {
            lastError = (error as? LAError)?.code == .userCancel ? nil : error.localizedDescription
        }
    }
}
