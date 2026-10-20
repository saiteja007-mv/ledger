import LocalAuthentication
import Observation
import Security
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

    /// `passcodeOnly` skips Face ID and asks for the iPhone passcode straight away.
    func unlock(passcodeOnly: Bool = false) async {
        guard !isPrompting else { return }
        isPrompting = true
        defer { isPrompting = false }

        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Not Now")
        let reason = String(localized: "Unlock Ledger")
        var error: NSError?
        // Falls back to the passcode when Face ID isn't set up or fails repeatedly.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = error?.localizedDescription ?? String(localized: "Face ID isn't available")
            return
        }
        do {
            // No LAPolicy is passcode-only; an access control that needs only the passcode is.
            if passcodeOnly, let passcode = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .devicePasscode, nil
            ) {
                isUnlocked = try await context.evaluateAccessControl(passcode, operation: .useItem, localizedReason: reason)
            } else {
                isUnlocked = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            }
            lastError = nil
        } catch {
            lastError = (error as? LAError)?.code == .userCancel ? nil : error.localizedDescription
        }
    }
}
