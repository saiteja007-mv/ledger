import Foundation

/// The two accounts a transfer leg moved money between.
///
/// A transfer is two rows, one on each account, and the other account is only written in text (the merchant
/// or the category). Read alone, "Visa 1004 -$1.99" looks like the card lost money when it was Checking
/// that paid it. This works out "from -> to" so lists can say so.
struct TransferRoute: Equatable, Sendable {
    let from: String
    let to: String
    /// The account this row belongs to: `from` for the leg money left, `to` for the leg it arrived on.
    let own: String

    var isOutgoing: Bool { own == from }
    var counterparty: String { isOutgoing ? to : from }

    /// nil for a row that isn't a transfer, or whose other account can't be found in its text.
    init?(_ transaction: LedgerTransaction, accountNames: [String]) {
        guard transaction.direction.isTransfer, let own = transaction.account, !own.isEmpty,
              let other = Self.otherAccount(in: transaction, own: own, accountNames: accountNames)
        else { return nil }
        self.own = own
        if transaction.direction == .transferOut {
            from = own
            to = other
        } else {
            from = other
            to = own
        }
    }

    private static func otherAccount(in transaction: LedgerTransaction, own: String, accountNames: [String]) -> String? {
        let others = accountNames.filter { $0.caseInsensitiveCompare(own) != .orderedSame }
        let fields = [transaction.merchant, transaction.category, transaction.subcategory]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // A field that is exactly an account's name ("Visa 1004", "Splitwise").
        for field in fields {
            if let name = others.first(where: { $0.caseInsensitiveCompare(field) == .orderedSame }) { return name }
        }
        // Text that mentions one ("Payment from Checking"): longest name first, and not tiny names,
        // so "Cash" doesn't match inside every sentence.
        let named = others.filter { $0.count >= 4 }.sorted { $0.count > $1.count }
        for field in fields {
            if let name = named.first(where: { field.range(of: $0, options: .caseInsensitive) != nil }) { return name }
        }
        return nil
    }
}
