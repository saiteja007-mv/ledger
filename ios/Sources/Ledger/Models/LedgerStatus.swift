/// Counts from get_status.
struct LedgerStatus: Decodable, Sendable {
    let transactions: Int
    let accounts: Int
    let receipts: Int
}
