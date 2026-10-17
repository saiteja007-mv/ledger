/// The answer of upload_receipt_photo: the new receipt, already queued to be read.
struct UploadResult: Decodable, Sendable {
    let id: Int
    let transactionId: Int?
    let billStatus: String?
}
