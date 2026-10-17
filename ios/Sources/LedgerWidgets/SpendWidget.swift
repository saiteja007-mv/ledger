import SwiftUI
import WidgetKit

/// "Spending": what you've spent this month against the overall limit. Small and medium are the yellow hero
/// card; the Lock Screen families show the same number as a gauge, a line, or text.
struct SpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LedgerSpend", provider: LedgerProvider()) { entry in
            SpendWidgetView(entry: entry)
        }
        .configurationDisplayName("Spending")
        .description("This month's spending against your monthly limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SpendWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LedgerEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: small(snapshot)
                case .systemMedium: medium(snapshot)
                case .accessoryCircular: circular(snapshot)
                case .accessoryRectangular: rectangular(snapshot)
                case .accessoryInline: inline(snapshot)
                default: small(snapshot)
                }
            } else {
                WidgetUnavailable(date: entry.date)
            }
        }
        .widgetURL(URL(string: "ledger://analysis"))
        .containerBackground(for: .widget) {
            switch family {
            case .systemSmall, .systemMedium: WidgetPalette.hero
            default: Color.clear
            }
        }
    }

    private var month: String {
        entry.date.formatted(.dateTime.month(.wide))
    }

    private func small(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Spent in \(month)").font(.caption.weight(.medium))
            Text(WidgetMoney.text(snapshot.summary.expenseCents, whole: true))
                .font(.system(size: 30, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 2)
            Spacer(minLength: 6)
            if let limit = snapshot.headline {
                WidgetBar(fraction: limit.fraction, tint: .black, track: .black.opacity(0.15))
                Text(limit.isTotal ? limit.leftText : "\(limit.category): \(limit.leftText)")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 5)
            } else {
                Text("Income \(WidgetMoney.text(snapshot.summary.incomeCents, whole: true))")
                    .font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ snapshot: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Spent in \(month)").font(.caption.weight(.medium))
                Text(WidgetMoney.text(snapshot.summary.expenseCents, whole: true))
                    .font(.system(size: 34, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.top, 2)
                Spacer(minLength: 6)
                Text("Income").font(.caption2)
                Text(WidgetMoney.text(snapshot.summary.incomeCents, whole: true))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                if let overall = snapshot.overall {
                    Text("Monthly limit").font(.caption.weight(.medium))
                    Text("\(overall.percent)%").font(.title2.weight(.bold))
                    WidgetBar(fraction: overall.fraction, tint: .black, track: .black.opacity(0.15))
                    Text(overall.isOver
                         ? "\(WidgetMoney.text(-overall.remainingCents, whole: true)) over"
                         : "\(WidgetMoney.text(overall.remainingCents, whole: true)) left of \(WidgetMoney.text(overall.limitCents, whole: true))")
                        .font(.caption2)
                        .lineLimit(2)
                } else if !snapshot.limits.isEmpty {
                    // No overall limit: the worst few category limits, as the Budget limits widget lists them.
                    Text("Monthly limits").font(.caption.weight(.medium))
                    ForEach(snapshot.limits.prefix(3)) { limit in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(limit.title).font(.caption2.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(limit.leftText).font(.caption2).lineLimit(1)
                            }
                            WidgetBar(fraction: limit.fraction, tint: .black, track: .black.opacity(0.15))
                        }
                    }
                } else {
                    Text("No budgets yet").font(.caption.weight(.medium))
                    Text("Set one in Budgets").font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.black)
    }

    private func circular(_ snapshot: WidgetSnapshot) -> some View {
        Gauge(value: snapshot.headline?.fraction ?? 0) {
            Image(systemName: "dollarsign")
        } currentValueLabel: {
            if let limit = snapshot.headline {
                Text("\(limit.percent)%")
            } else {
                Text(WidgetMoney.text(snapshot.summary.expenseCents, whole: true)).minimumScaleFactor(0.5)
            }
        }
        .gaugeStyle(.accessoryCircular)
    }

    private func rectangular(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Spent in \(month)").font(.caption2)
            Text(WidgetMoney.text(snapshot.summary.expenseCents, whole: true)).font(.headline)
            if let limit = snapshot.headline {
                Gauge(value: limit.fraction) { EmptyView() }
                    .gaugeStyle(.accessoryLinear)
                Text("\(limit.title) \(limit.percent)% of \(WidgetMoney.text(limit.limitCents, whole: true))")
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
    }

    private func inline(_ snapshot: WidgetSnapshot) -> some View {
        if let limit = snapshot.headline {
            Text("Spent \(WidgetMoney.text(snapshot.summary.expenseCents, whole: true)) · \(limit.percent)%")
        } else {
            Text("Spent \(WidgetMoney.text(snapshot.summary.expenseCents, whole: true))")
        }
    }
}
