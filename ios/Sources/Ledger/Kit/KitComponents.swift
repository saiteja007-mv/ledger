import SwiftUI

// MARK: Amounts

/// The kit's big figure: a small "$", the whole part large, the cents small ("$ 2,850 .00").
struct KitAmountView: View {
    enum Size {
        case hero, large, medium

        var whole: Font {
            switch self {
            case .hero: .kit(.medium, 56, relativeTo: .largeTitle)
            case .large: .kit(.medium, 40, relativeTo: .largeTitle)
            case .medium: .kit(.medium, 24, relativeTo: .title2)
            }
        }

        var small: Font {
            switch self {
            case .hero: .kit(.medium, 24, relativeTo: .title2)
            case .large: .kit(.medium, 18, relativeTo: .headline)
            case .medium: .kit(.medium, 14, relativeTo: .subheadline)
            }
        }
    }

    let cents: Int
    var currency: String?
    var size = Size.hero
    /// Shows a leading "-" for money out.
    var isNegative = false

    private var symbol: String {
        let code = currency ?? "USD"
        return code == "USD" ? "$" : code
    }

    var body: some View {
        let magnitude = abs(cents)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if isNegative {
                Text("-").font(size.whole)
            }
            Text(symbol).font(size.small)
            Text((magnitude / 100).formatted(.number.grouping(.automatic)))
                .font(size.whole)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("." + String(format: "%02d", magnitude % 100)).font(size.small)
        }
        .foregroundStyle(KitColor.label.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Money.text(cents, currency: currency)))
    }
}

// MARK: Rows

/// One transaction as the kit lists it: avatar, merchant over category, the amount at the right (green for money in).
///
/// A transfer leg is drawn differently, because it is not spending or income: a neutral arrows avatar, the
/// route ("Checking → Visa 1004") with this row's own account in medium weight, and an amount that keeps
/// its +/- (what happened to that account) but isn't coloured as income.
struct KitTransactionRow: View {
    let transaction: LedgerTransaction

    @Environment(LedgerStore.self) private var store

    private var route: TransferRoute? {
        TransferRoute(transaction, accountNames: store.accounts.map(\.name))
    }

    /// The symbol first, then the amount, in the row's own currency ("- $7.15", "+ €12.00").
    private var amount: String {
        let text = Money.text(transaction.amountCents, currency: transaction.currency)
        switch transaction.direction {
        case .income, .transferIn: return "+ " + text
        case .expense, .transferOut: return "- " + text
        }
    }

    /// What the bank or assistant called it, unless that is just the other account's name.
    private var title: String {
        guard let route else { return transaction.title }
        let merchant = transaction.merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !merchant.isEmpty, merchant.caseInsensitiveCompare(route.counterparty) != .orderedSame { return merchant }
        return route.isOutgoing
            ? String(localized: "Transfer to \(route.counterparty)")
            : String(localized: "Transfer from \(route.counterparty)")
    }

    private func routeText(_ route: TransferRoute) -> AttributedString {
        var from = AttributedString(route.from)
        var to = AttributedString(route.to)
        if route.isOutgoing { from.font = .kitSmallMedium } else { to.font = .kitSmallMedium }
        return from + AttributedString(" → ") + to
    }

    var body: some View {
        HStack(spacing: 12) {
            if transaction.direction.isTransfer {
                KitAvatar(category: transaction.title, isTransfer: true)
            } else {
                KitAvatar(category: transaction.category ?? transaction.title, merchant: transaction.merchant)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(title).font(.kitBodyMedium).lineLimit(1)
                    if transaction.reviewed == false {
                        Circle().fill(KitColor.warning.color).frame(width: 7, height: 7)
                            .accessibilityLabel("Not reviewed")
                    }
                }
                Group {
                    if let route {
                        Text(routeText(route))
                    } else if transaction.direction.isTransfer {
                        Text("Transfer · \(transaction.account ?? "")")
                    } else {
                        Text(transaction.category.map(CategoryName.display) ?? transaction.account ?? "")
                    }
                }
                .font(.kitSmall)
                .foregroundStyle(KitColor.secondary.color)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(amount)
                .font(.kitBodyMedium)
                .monospacedDigit()
                .foregroundStyle(
                    transaction.direction.isTransfer || transaction.direction.sign < 0
                        ? KitColor.label.color : KitColor.positive.color
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(KitColor.label.color)
        .accessibilityElement(children: .combine)
    }
}

/// A settings-style row: a line icon, a title with an optional secondary line, and a chevron.
struct KitMenuRow: View {
    let icon: KitIcon
    let title: LocalizedStringKey
    var subtitle: String?
    var value: String?
    var badge = 0
    var showsChevron = true
    var tint: Color?

    var body: some View {
        HStack(spacing: 16) {
            KitIconView(icon: icon, height: 24, color: tint ?? KitColor.label.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.kitBodyMedium).foregroundStyle(tint ?? KitColor.label.color)
                if let subtitle {
                    Text(subtitle).font(.kitSmall).foregroundStyle(KitColor.secondary.color).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if badge > 0 {
                Text("\(badge)")
                    .font(.kit(.medium, 12, relativeTo: .caption))
                    .foregroundStyle(KitColor.white)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 22)
                    .background(KitColor.accent.color, in: .capsule)
            }
            if let value {
                Text(value).font(.kitSmall).foregroundStyle(KitColor.secondary.color).lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(KitColor.label.color)
            }
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

/// A centred grey label between groups ("Personal info", "Today", "April").
struct KitSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.kitSmall)
            .foregroundStyle(KitColor.secondary.color)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: Controls

/// Graph / List: a grey track with a blue pill under the chosen one.
struct KitSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.kitBodyMedium)
                        .foregroundStyle(isSelected ? KitColor.white : KitColor.label.color)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KitColor.accentStrong.color)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(KitColor.surface.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The kit's black, full-width action ("Confirm", "Complete", "Save"). White in dark mode.
struct KitPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.kitBodyMedium)
            .foregroundStyle(KitColor.background.color)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(KitColor.label.color.opacity(isEnabled ? 1 : 0.3), in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension View {
    /// The kit's underlined input: no box, a hairline underneath.
    func kitUnderlinedField() -> some View {
        self.font(.kitBody)
            .foregroundStyle(KitColor.label.color)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(KitColor.label.color).frame(height: 1)
            }
    }

    /// The kit's quiet card: Neutral/200, 20 pt corners.
    func kitCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KitColor.surface.color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// A `List` or `Form` inside the kit's page: no grouped background, the kit's type and ink.
    func kitList() -> some View {
        self.scrollContentBackground(.hidden)
            .font(.kitBody)
            .foregroundStyle(KitColor.label.color)
    }

    /// Quiet rows for a list: the page colour with the kit's hairline.
    func kitRows() -> some View {
        self.listRowBackground(KitColor.background.color)
            .listRowSeparatorTint(KitColor.separator.color)
    }
}

// MARK: Banner, bars, ring

/// The blue card with a coin: "Add your card or account" in the kit, a prompt to review or add here.
struct KitBanner: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            KitCoin(size: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.kitBodyMedium)
                Text(subtitle).font(.kitSmall).opacity(0.9)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(KitColor.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KitColor.accent.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Bars over labels, the chosen one in the strong blue with its value above it.
struct KitBars: View {
    struct Bar: Identifiable {
        let id: Int
        let label: String
        let value: Double
        let valueText: String
    }

    let bars: [Bar]
    /// The highlighted bar; the busiest when nil.
    var selected: Int?
    var height: CGFloat = 120
    /// Called with a bar's id when it's tapped; the bars aren't buttons when nil.
    var onSelect: ((Int) -> Void)?

    private var chosen: Int? {
        selected ?? bars.max { $0.value < $1.value }?.id
    }

    var body: some View {
        let top = max(bars.map(\.value).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(bars) { bar in
                if let onSelect {
                    Button { onSelect(bar.id) } label: { column(bar, top: top) }
                        .buttonStyle(.plain)
                } else {
                    column(bar, top: top)
                }
            }
        }
        .frame(height: height)
    }

    private func column(_ bar: Bar, top: Double) -> some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            if bar.id == chosen, bar.value > 0 {
                Text(bar.valueText).font(.kitCaption).foregroundStyle(KitColor.label.color).lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(bar.id == chosen ? KitColor.accentStrong.color : KitColor.accentSoft.color)
                .frame(height: max(8, CGFloat(bar.value / top) * (height - 44)))
            Text(bar.label)
                .font(bar.id == chosen ? .kit(.medium, 12, relativeTo: .caption) : .kitCaption)
                .foregroundStyle(bar.id == chosen ? KitColor.label.color : KitColor.secondary.color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(bar.label): \(bar.valueText)"))
        .accessibilityAddTraits(bar.id == chosen ? .isSelected : [])
    }
}

/// The statistics ring: a grey track split into one arc per category, the chosen arc blue.
struct KitRing: View {
    let fractions: [Double]
    let selected: Int
    var lineWidth: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let total = max(fractions.reduce(0, +), 0.0001)
            let gap = fractions.count > 1 ? 0.008 : 0
            ZStack {
                ForEach(Array(fractions.enumerated()), id: \.offset) { index, value in
                    let start = fractions[..<index].reduce(0, +) / total
                    let end = start + value / total
                    Circle()
                        .trim(from: start + gap / 2, to: max(start + gap / 2, end - gap / 2))
                        .stroke(
                            index == selected ? KitColor.accent.color : KitColor.surface.color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: side - lineWidth, height: side - lineWidth)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// A thin progress line: the kit's "Monthly payment limit".
struct KitMeter: View {
    let fraction: Double
    var tint: Color = KitColor.accentStrong.color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(KitColor.tintStrong.color)
                Capsule().fill(tint).frame(width: max(6, min(max(fraction, 0), 1) * proxy.size.width))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
