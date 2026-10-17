/// One line on a receipt or a bill. Prices are dollars; a discount is negative.
struct LineItem: Decodable, Hashable, Sendable {
    let name: String
    let qty: Double?
    /// The line total.
    let price: Double?
    let unit: String?
    let unitPrice: Double?
}
