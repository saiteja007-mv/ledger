import SwiftUI

/// A decimal amount field whose value updates on every keystroke. `TextField(value:format:)`
/// writes back only when editing ends, which would keep Save disabled until you tapped elsewhere.
struct AmountField: View {
    let title: LocalizedStringResource
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        TextField(text: $text) {
            Text(title)
        }
        .keyboardType(.decimalPad)
        .monospacedDigit()
        .onChange(of: text) { _, newText in
            value = Money.parseAmount(newText)
        }
        .onAppear(perform: showInitialValue)
    }

    /// Shows a prefilled value, such as an existing budget's limit.
    private func showInitialValue() {
        if text.isEmpty, let value {
            text = value.formatted()
        }
    }
}
