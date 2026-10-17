import Foundation

/// The Log Spending form. Becomes one upsert_transactions item.
struct NewTransaction: Sendable {
    var amount: Double?
    var direction = Direction.expense
    var merchant = ""
    var category: String?
    var account = ""
    /// The other side of a transfer; empty for none.
    var counterAccount = ""
    var currency = "USD"
    var date = Date.now
    var note = ""

    var cents: Int {
        Int(((amount ?? 0) * 100).rounded())
    }

    var isValid: Bool {
        cents > 0 && !account.isEmpty && currency.count == 3
    }

    /// The upsert item. posted_at keeps seconds: it is part of the dedup key, so two equal
    /// purchases a minute apart stay two rows.
    var item: JSONValue {
        let merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return .fields([
            "account": .string(account),
            "posted_at": .string(LedgerDate.stamp(date)),
            "direction": .string(direction.rawValue),
            "amount_cents": .int(cents),
            "currency": .string(currency.uppercased()),
            "merchant": merchant.isEmpty ? nil : .string(merchant),
            "category": category.map(JSONValue.string),
            "note": note.isEmpty ? nil : .string(note),
            "counter_account": direction.isTransfer && !counterAccount.isEmpty ? .string(counterAccount) : nil,
        ])
    }
}
