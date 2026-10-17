/// Why one row of an upsert was not written.
struct RowError: Decodable, Sendable {
    let index: Int
    let error: String
}
