/// Spending in one category over a period, from category_breakdown.
struct CategoryTotal: Decodable, Identifiable, Sendable {
    let category: String
    let count: Int
    let totalCents: Int

    var id: String { category }
}

extension [CategoryTotal] {
    /// The category whose donut slice contains `angle`: cents counted from the start of the first
    /// slice, in the order the slices are drawn (the order of this array).
    func category(atAngle angle: Int) -> String? {
        guard angle >= 0 else { return nil }
        var end = 0
        for total in self {
            end += total.totalCents
            if angle < end { return total.category }
        }
        return nil
    }
}
