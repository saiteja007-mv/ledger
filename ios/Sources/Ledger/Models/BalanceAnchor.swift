/// A reported balance on a date, as the networth extra embeds it.
struct BalanceAnchor: Decodable, Hashable, Sendable {
    let asOfDate: String
    let cents: Int
}
