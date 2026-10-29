import SwiftUI

/// The add field at the top of the list: a name, an optional quantity and a plus button. Return adds too.
struct ShoppingAddRow: View {
    @Binding var name: String
    @Binding var qty: String
    let canAdd: Bool
    let add: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let layout = isLarge ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            TextField("Add an item", text: $name)
                .font(.kitBody)
                .frame(minHeight: 44)
                .submitLabel(.done)
                .onSubmit(add)
            TextField("Qty", text: $qty)
                .font(.kitBody)
                .keyboardType(.decimalPad)
                .frame(maxWidth: isLarge ? .infinity : 72, minHeight: 44)
            Button("Add", systemImage: "plus.circle.fill", action: add)
                .labelStyle(.iconOnly)
                .font(.title2)
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!canAdd)
        }
    }
}
