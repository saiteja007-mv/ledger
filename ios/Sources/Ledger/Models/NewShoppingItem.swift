import Foundation

/// What the add field on the Shopping List holds: a name and, optionally, how many.
struct NewShoppingItem: Hashable, Sendable {
    var name: String
    var qty: Double?

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isValid: Bool { !trimmedName.isEmpty && (qty ?? 1) > 0 }

    /// One `add` entry for update_shopping_list; no `qty` key when none was typed.
    var json: JSONValue {
        .fields(["name": .string(trimmedName), "qty": qty.map(JSONValue.double)])
    }
}
