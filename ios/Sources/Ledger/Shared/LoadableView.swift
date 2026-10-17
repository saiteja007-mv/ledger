import SwiftUI

/// A whole screen's content: a spinner while loading, a full-screen error with Try Again on failure.
struct LoadableView<Value: Sendable, Content: View>: View {
    let state: Loadable<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let value):
            content(value)
        case .failed(let error):
            ErrorStateView(error: error, retry: retry)
        }
    }
}
