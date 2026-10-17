/// A rule-based category guess for one transaction, from suggest_categories. Nothing is written until you apply it.
struct CategorySuggestion: Decodable, Identifiable, Sendable {
    /// The transaction id.
    let id: Int
    let category: String
    /// The merchant or note text that matched.
    let rule: String
    let confidence: Double
}
