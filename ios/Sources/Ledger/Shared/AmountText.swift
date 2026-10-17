import SwiftUI

/// A transaction amount with its sign: "−$12.50" out, "+$12.50" in (in green).
struct AmountText: View {
    let cents: Int
    let currency: String?
    let direction: Direction

    var body: some View {
        Text(Money.signed(cents, currency: currency, direction: direction))
            .monospacedDigit()
            .foregroundStyle(direction == .income ? Theme.moneyIn : .primary)
    }
}
