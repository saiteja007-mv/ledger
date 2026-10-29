import SwiftUI

/// Above the rows: how many things to buy and, when some have a price, the estimated total.
struct ShoppingListHeader: View {
    let count: Int
    let estimatedTotalCents: Int?

    var body: some View {
        HStack {
            Text("^[\(count) item](inflect: true)")
            Spacer()
            if let estimatedTotalCents {
                Text("Est. total \(Money.text(estimatedTotalCents))").monospacedDigit()
            }
        }
        .font(.kitSmall)
        .foregroundStyle(KitColor.secondary.color)
        .textCase(nil)
    }
}
