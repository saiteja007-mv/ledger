import SwiftUI

/// The kit's screen: a quiet top bar (back, centred title, one trailing action) over either the plain page
/// or, with `tinted`, the pale-blue header with the swirl and a white sheet that curves over it.
///
/// A `hero` sits between the bar and the sheet (the merchant and amount on a transaction, the avatar on
/// the account). The nav bar sits under the screens in the root's layout, so content ends above it and needn't add its own.
struct KitScreen<Trailing: View, Hero: View, Content: View>: View {
    var title: String?
    var showsBack = false
    var tinted = false
    private let trailing: Trailing
    private let hero: Hero
    private let content: Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(
        _ title: String? = nil, showsBack: Bool = false, tinted: Bool = false,
        @ViewBuilder trailing: () -> Trailing, @ViewBuilder hero: () -> Hero, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.showsBack = showsBack
        self.tinted = tinted
        self.trailing = trailing()
        self.hero = hero()
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            (tinted ? KitColor.tint.color : KitColor.background.color).ignoresSafeArea()
            if tinted {
                KitSwirl(
                    cut: .screen,
                    fill: scheme == .dark ? KitColor.accent.color : KitColor.tintStrong.color,
                    outline: scheme == .dark ? nil : KitColor.black
                )
                .frame(height: 360)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
            }
            VStack(spacing: 0) {
                if title != nil || showsBack {
                    topBar
                }
                hero
                if tinted {
                    sheet
                } else {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        ZStack {
            if let title {
                Text(title)
                    .font(.kitBodyMedium)
                    .foregroundStyle(KitColor.label.color)
                    .lineLimit(1)
                    .padding(.horizontal, 64)
            }
            HStack {
                if showsBack {
                    Button(action: { dismiss() }) {
                        KitIconView(icon: .arrowLeft, height: 24, color: KitColor.label.color)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Back")
                }
                Spacer()
                trailing
            }
            .padding(.horizontal, 12)
        }
        .frame(minHeight: 44)
    }

    private var sheet: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: KitMetrics.sheetRadius, topTrailingRadius: KitMetrics.sheetRadius)
                    .fill(KitColor.background.color)
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: KitMetrics.sheetRadius, topTrailingRadius: KitMetrics.sheetRadius)
                            .stroke(scheme == .dark ? KitColor.separator.color : .clear, lineWidth: 1)
                    }
                    .ignoresSafeArea(edges: .bottom)
            }
    }
}

extension KitScreen where Trailing == EmptyView, Hero == EmptyView {
    init(_ title: String? = nil, showsBack: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title, showsBack: showsBack, tinted: false, trailing: { EmptyView() }, hero: { EmptyView() }, content: content)
    }
}

extension KitScreen where Hero == EmptyView {
    init(
        _ title: String? = nil, showsBack: Bool = false,
        @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content
    ) {
        self.init(title, showsBack: showsBack, tinted: false, trailing: trailing, hero: { EmptyView() }, content: content)
    }
}

extension KitScreen where Trailing == EmptyView {
    /// The tinted screen: pale header with the swirl, `hero` under the bar, a curved white sheet for `content`.
    init(
        _ title: String? = nil, showsBack: Bool = false, @ViewBuilder hero: () -> Hero, @ViewBuilder content: () -> Content
    ) {
        self.init(title, showsBack: showsBack, tinted: true, trailing: { EmptyView() }, hero: hero, content: content)
    }
}

enum KitMetrics {
    /// The curved sheet's top radius under a tinted header.
    static let sheetRadius: CGFloat = 40
    static let cardRadius: CGFloat = 32
    static let margin: CGFloat = 20
}

/// A 44 pt icon button for the top bar (calendar, plus, search).
struct KitBarButton: View {
    let icon: KitIcon
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KitIconView(icon: icon, height: 24, color: KitColor.label.color)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
    }
}
