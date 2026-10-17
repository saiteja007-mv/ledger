import SwiftUI

/// Opening + ledger movement = expected closing, against the reported closing.
struct ReconciliationRows: View {
    let reconciliation: Reconciliation

    var body: some View {
        Group {
            LabeledContent("Opening") { money(reconciliation.openingCents) }
            LabeledContent("Ledger movement") { money(reconciliation.ledgerMovementCents) }
            LabeledContent("Expected closing") { money(reconciliation.expectedClosingCents) }
            LabeledContent("Reported closing") { money(reconciliation.closingCents) }
            LabeledContent("Drift") { money(reconciliation.driftCents) }
        }
        if reconciliation.withinTolerance {
            Label("Balanced, across ^[\(reconciliation.transactionCount) transaction](inflect: true)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.moneyIn)
        } else {
            Label("Off by \(Money.text(reconciliation.driftCents))", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func money(_ cents: Int) -> Text {
        Text(Money.text(cents)).monospacedDigit()
    }
}
