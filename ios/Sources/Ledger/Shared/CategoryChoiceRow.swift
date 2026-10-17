import SwiftUI

/// One category in the picker, with its kit avatar, checked when it's the current one.
struct CategoryChoiceRow: View {
    let name: String
    let isCurrent: Bool
    let pick: (String) -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 14) {
                KitAvatar(category: name)
                Text(CategoryName.display(name))
                    .font(.kitBodyMedium)
                    .foregroundStyle(KitColor.label.color)
                    .lineLimit(1)
                Spacer()
                if isCurrent {
                    KitIconView(icon: .checkmark, height: 24, color: KitColor.accent.color)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func choose() {
        pick(name)
    }
}
