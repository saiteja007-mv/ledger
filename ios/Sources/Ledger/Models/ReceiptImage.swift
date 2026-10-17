import Foundation

/// A receipt photo from get_receipt_image, downscaled on the server.
struct ReceiptImage: Decodable, Sendable {
    let receiptId: Int
    let imageBase64: String
    let mimeType: String

    var data: Data? {
        Data(base64Encoded: imageBase64)
    }
}
