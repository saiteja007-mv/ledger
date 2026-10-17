import Foundation

/// A Log Spending link from Siri, Shortcuts, an automation or a widget:
/// `ledger://add?amount=12.50&merchant=Starbucks&category=Food&account=Checking%201234`.
/// Every part is optional; the form opens with what was given and you confirm it.
enum QuickLog {
    /// The draft a link describes, or nil when it carries nothing to fill in (a plain `ledger://add`).
    static func draft(from url: URL) -> NewTransaction? {
        guard url.scheme == "ledger", url.host() == "add",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, !items.isEmpty
        else { return nil }

        func value(_ name: String) -> String? {
            let text = items.first { $0.name.lowercased() == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        }

        var draft = NewTransaction()
        draft.amount = value("amount").flatMap(amount)
        draft.merchant = value("merchant") ?? ""
        draft.category = value("category")
        draft.account = value("account") ?? ""
        draft.note = value("note") ?? ""
        if let currency = value("currency")?.uppercased(), currency.count == 3 { draft.currency = currency }
        switch value("type")?.lowercased() {
        case "income": draft.direction = .income
        case "transfer": draft.direction = .transferOut
        default: draft.direction = .expense
        }
        draft.counterAccount = value("to") ?? ""
        if let date = value("date").flatMap({ LedgerDate.parse($0) }) {
            // A date alone means that day at noon, so it never slips a day across time zones.
            draft.date = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        }
        return draft
    }

    /// "12.5", "$12.50", "1,234.50" -> a positive amount. Shortcuts hands numbers over as plain text.
    static func amount(_ text: String) -> Double? {
        let digits = text.filter { $0.isNumber || $0 == "." }
        guard let value = Double(digits), value > 0 else { return nil }
        return value
    }
}
