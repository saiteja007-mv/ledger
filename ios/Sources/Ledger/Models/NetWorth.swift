/// The `networth` extra: every account's balance as of now, grouped, and the USD total.
/// Same numbers the web app shows.
struct NetWorth: Decodable, Sendable {
    let assetsCents: Int
    let liabilitiesCents: Int
    let netCents: Int
    /// Accounts with no reported balance yet; their figure is the ledger sum alone.
    let unverifiedCount: Int
    let groups: [NetWorthGroup]

    var accounts: [AccountBalance] {
        groups.flatMap(\.accounts)
    }
}
