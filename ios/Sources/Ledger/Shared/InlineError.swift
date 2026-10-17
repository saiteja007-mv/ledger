import SwiftUI

/// A failed part of a screen, as one list row, while the rest of the screen still shows.
struct InlineError: View {
    let error: LedgerError

    var body: some View {
        Label(error.message, systemImage: error.systemImage)
            .foregroundStyle(.secondary)
    }
}
