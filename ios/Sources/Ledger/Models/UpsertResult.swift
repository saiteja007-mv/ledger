/// The answer of upsert_transactions. Re-sending a row updates it instead of duplicating it.
struct UpsertResult: Decodable, Sendable {
    let inserted: Int
    let updated: Int
    let errors: [RowError]
    let ids: [Int]
}
