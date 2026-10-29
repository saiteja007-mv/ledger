import SwiftUI

/// "Running low  3". The Not tracked header folds its section away: give it `isExpanded` and `toggle`.
struct InventorySectionHeader: View {
    let section: InventorySection
    let count: Int
    /// nil for a section that always shows its items.
    var isExpanded: Bool?
    var toggle: () -> Void = {}

    var body: some View {
        if let isExpanded {
            Button(action: toggle) {
                title(chevron: isExpanded)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
        } else {
            title(chevron: nil)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func title(chevron isExpanded: Bool?) -> some View {
        HStack(spacing: 8) {
            Text(section.title).font(.kitSubtitle)
            Text(count.formatted()).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
            Spacer(minLength: 8)
            if let isExpanded {
                Image(systemName: "chevron.down")
                    .font(.kitSmall)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(KitColor.label.color)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
    }
}
