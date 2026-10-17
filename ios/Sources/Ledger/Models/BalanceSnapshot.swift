/// A reported balance, from list_balances: the independent anchor reconciliation checks the ledger against.
struct BalanceSnapshot: Decodable, Identifiable, Sendable {
    let accountId: Int
    let account: String
    let asOfDate: String
    let balanceCents: Int
    let currency: String

    var id: String { "\(accountId)|\(asOfDate)" }
}
