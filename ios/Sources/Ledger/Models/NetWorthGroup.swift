/// Banking, Cards, Cash or People, with its accounts and their total contribution to net worth.
struct NetWorthGroup: Decodable, Identifiable, Sendable {
    let key: String
    let label: String
    let totalCents: Int
    let accounts: [AccountBalance]

    var id: String { key }
}
