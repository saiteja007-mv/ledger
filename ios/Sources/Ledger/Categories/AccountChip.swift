import SwiftUI

/// An account's name as a small capsule, so a row says which account paid at a glance.
struct AccountChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.kit(.regular, 13, relativeTo: .footnote))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
    }
}
