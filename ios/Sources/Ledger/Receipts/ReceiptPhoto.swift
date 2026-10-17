import UIKit

/// Prepares a receipt photo for upload: at most 2400 px on the long edge, JPEG.
/// That is plenty to read a receipt and keeps a 48 MP shot from becoming a 16 MB upload.
enum ReceiptPhoto {
    static let maxEdge = 2400.0

    static func jpeg(from image: UIImage) -> Data? {
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let resized = scale < 1 ? image.preparingThumbnail(of: target) ?? image : image
        return resized.jpegData(compressionQuality: 0.8)
    }
}
