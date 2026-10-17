/// One account from the `networth` extra.
struct AccountBalance: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let currency: String
    let transactions: Int
    /// checking, credit, cash, people or other.
    let kindResolved: String
    /// A card: `currentCents` is what you owe.
    let isLiability: Bool
    /// Has at least one reported balance to anchor it.
    let verified: Bool
    /// The latest reported balance, the anchor for `currentCents`.
    let latestBalance: BalanceAnchor?
    /// Ledger movement after the anchor date, in the account's own convention.
    let driftCents: Int?
    /// The balance as of now, in the account's own currency and convention.
    let currentCents: Int
    /// The contribution to net worth in USD (negative for money owed).
    let signedCents: Int
}
