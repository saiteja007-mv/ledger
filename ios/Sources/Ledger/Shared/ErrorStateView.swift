import SwiftUI

/// "Ledger API unreachable (Tailscale off?)" and friends, with a way to try again.
struct ErrorStateView: View {
    let error: LedgerError
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.message, systemImage: error.systemImage)
        } description: {
            switch error {
            case .unreachable: Text("Turn on Tailscale on this iPhone, then try again.")
            case .apiDown: Text("Your server answered, but ledger-api isn't running. Check `systemctl --user status ledger-api` there.")
            default: EmptyView()
            }
        } actions: {
            Button("Try Again", systemImage: "arrow.clockwise", action: retryTapped)
                .buttonStyle(.borderedProminent)
        }
    }

    private func retryTapped() {
        Task { await retry() }
    }
}
