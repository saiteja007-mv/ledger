/// Whether the ledger explains the change between two reported balances, from reconcile_account.
/// Non-zero drift means a row is missing, duplicated or invented.
struct Reconciliation: Decodable, Sendable {
    let account: String
    let from: String
    let to: String
    let openingCents: Int
    let closingCents: Int
    let ledgerMovementCents: Int
    let expectedClosingCents: Int
    let driftCents: Int
    let balanced: Bool
    /// Off by no more than FX rounding.
    let withinTolerance: Bool
    let transactionCount: Int
}
