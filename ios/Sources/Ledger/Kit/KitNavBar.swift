import SwiftUI

/// The kit's tab bar: line icon over a label, the current one on a yellow tile with its label in medium.
/// It's installed once, under the screens in the root's layout, so every pushed screen has it.
struct KitNavBar: View {
    @Binding var selection: AppTab
    /// Shown on the More tab: reviews waiting.
    var badge = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            ZStack {
                                if tab == selection {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KitColor.yellow)
                                }
                                KitIconView(
                                    icon: tab.icon, height: 24,
                                    color: tab == selection ? KitColor.black : KitColor.secondary.color
                                )
                            }
                            .frame(width: 44, height: 36)
                            if tab == .more, badge > 0 {
                                Text(badge < 100 ? "\(badge)" : "99+")
                                    .font(.kit(.medium, 11, relativeTo: .caption2))
                                    .foregroundStyle(KitColor.white)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(KitColor.accent.color, in: .capsule)
                                    .offset(x: 4, y: -4)
                            }
                        }
                        Text(tab.title)
                            .font(tab == selection ? .kit(.medium, 12, relativeTo: .caption) : .kitCaption)
                            .foregroundStyle(tab == selection ? KitColor.label.color : KitColor.secondary.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background {
            KitColor.background.color
                .overlay(alignment: .top) {
                    Rectangle().fill(KitColor.separator.color).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
