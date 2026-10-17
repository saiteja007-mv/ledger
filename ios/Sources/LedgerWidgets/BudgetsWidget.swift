import SwiftUI
import WidgetKit

/// "Budget limits": the overall limit and then the worst categories, each as a bar with what's left.
struct BudgetsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LedgerBudgets", provider: LedgerProvider()) { entry in
            BudgetsWidgetView(entry: entry)
        }
        .configurationDisplayName("Budget limits")
        .description("Your monthly limits with what's left, worst first.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct BudgetsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LedgerEntry

    private var rowCount: Int {
        family == .systemLarge ? 6 : 3
    }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                WidgetUnavailable(date: entry.date)
            }
        }
        .widgetURL(URL(string: "ledger://budgets"))
        .containerBackground(WidgetPalette.background, for: .widget)
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        let shown = Array(snapshot.limits.prefix(rowCount))
        VStack(alignment: .leading, spacing: 10) {
            Text("Monthly limits")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WidgetPalette.label)
            if shown.isEmpty {
                Text("No budgets yet.")
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(shown) { budget in
                    row(budget)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ budget: WidgetBudget) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(budget.isTotal ? "All spending" : budget.category)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WidgetPalette.label)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(budget.isOver
                     ? "\(WidgetMoney.text(-budget.remainingCents)) over"
                     : "\(WidgetMoney.text(budget.remainingCents)) of \(WidgetMoney.text(budget.limitCents, whole: true))")
                    .font(.caption2)
                    .foregroundStyle(budget.isOver ? WidgetPalette.destructive : WidgetPalette.secondary)
                    .lineLimit(1)
            }
            WidgetBar(fraction: budget.fraction, tint: WidgetPalette.tint(for: budget))
        }
        .accessibilityElement(children: .combine)
    }
}
