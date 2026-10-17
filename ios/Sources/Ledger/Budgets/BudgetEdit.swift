import Foundation

/// A budget being set: blank for a new one, prefilled to change an existing one.
struct BudgetEdit: Identifiable {
    let id = UUID()
    var category: String?
    var period: String
    var limitCents: Int?
}
