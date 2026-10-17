import SwiftUI

/// A budget as the kit's "Monthly payment limit": a coin or the category's avatar, the name, a thin line,
/// and "Remained $12 of $20". Status shows as an icon as well as a colour.
struct BudgetRow: View {
    let budget: BudgetStatus

    private var name: String {
        budget.isTotal ? String(localized: "Monthly limit") : CategoryName.display(budget.category)
    }

    private var tint: Color {
        switch budget.status {
        case "over": KitColor.destructive.color
        case "warning": KitColor.warning.color
        default: KitColor.accentStrong.color
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            if budget.isTotal {
                KitCoin(size: 44)
            } else {
                KitAvatar(category: budget.category, size: 44)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name).font(.kitBodyMedium).lineLimit(1)
                    Image(systemName: budget.systemImage).font(.caption).foregroundStyle(tint).accessibilityHidden(true)
                }
                KitMeter(fraction: Double(budget.spentCents) / Double(max(budget.limitCents, 1)), tint: tint)
                Group {
                    if budget.remainingCents >= 0 {
                        Text("Remained \(Text(Money.text(budget.remainingCents)).font(.kitSmallMedium).foregroundStyle(KitColor.label.color)) of \(Text(Money.text(budget.limitCents)).font(.kitSmallMedium).foregroundStyle(KitColor.label.color))")
                    } else {
                        Text("\(Text(Money.text(-budget.remainingCents)).font(.kitSmallMedium).foregroundStyle(KitColor.destructive.color)) over \(Text(Money.text(budget.limitCents)).font(.kitSmallMedium).foregroundStyle(KitColor.label.color))")
                    }
                }
                .font(.kitSmall)
                .foregroundStyle(KitColor.secondary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(KitColor.label.color)
        .accessibilityElement(children: .combine)
    }
}
