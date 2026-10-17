import Foundation

/// The brand icon ledger-api found for a merchant descriptor (`merchant_logo`): a PNG, or no domain at all
/// when the merchant is a person, a transfer or a brand it doesn't know.
struct MerchantLogo: Decodable, Sendable {
    let domain: String?
    let imageBase64: String?

    var data: Data? {
        imageBase64.flatMap { Data(base64Encoded: $0) }
    }
}
