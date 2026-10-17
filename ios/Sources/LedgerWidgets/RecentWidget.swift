import SwiftUI
import WidgetKit

/// "Recent": the newest transactions, with a + that opens Log Spending.
struct RecentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LedgerRecent", provider: LedgerProvider()) { entry in
            RecentWidgetView(entry: entry)
        }
        .configurationDisplayName("Recent")
        .description("Your latest transactions, and a shortcut to log spending.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct RecentWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LedgerEntry

    private var rowCount: Int {
        family == .systemLarge ? 7 : 3
    }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                WidgetUnavailable(date: entry.date)
            }
        }
        .widgetURL(URL(string: "ledger://activity"))
        .containerBackground(WidgetPalette.background, for: .widget)
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WidgetPalette.label)
                Spacer()
                Link(destination: URL(string: "ledger://add")!) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(WidgetPalette.hero, in: .circle)
                }
                .accessibilityLabel("Log Spending")
            }
            let shown = Array(snapshot.recent.prefix(rowCount))
            if shown.isEmpty {
                Text("Nothing logged yet.")
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondary)
            } else {
                ForEach(shown) { transaction in
                    row(transaction)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ transaction: WidgetTransaction) -> some View {
        HStack(spacing: 10) {
            Text(String(transaction.title.prefix(1)).uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.label)
                .frame(width: 28, height: 28)
                .background(WidgetPalette.surface, in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                Text(transaction.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WidgetPalette.label)
                    .lineLimit(1)
                Text(transaction.category ?? transaction.account ?? "")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text((transaction.isMoneyIn ? "+ " : "- ") + WidgetMoney.text(transaction.amountCents, currency: transaction.currency))
                .font(.caption.weight(.semibold))
                .foregroundStyle(transaction.isMoneyIn ? WidgetPalette.positive : WidgetPalette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}
