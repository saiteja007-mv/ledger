import SwiftUI

/// Reading, read, failed, and whether the receipt is attached to a transaction.
struct BillStatusLabel: View {
    let receipt: Receipt

    var body: some View {
        Group {
            if receipt.isReading {
                Label("Reading the photo…", systemImage: "hourglass")
            } else if receipt.billStatus == "failed" {
                Label("Couldn't read the photo", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if receipt.transactionId == nil {
                Label("Not attached to a transaction", systemImage: "link.badge.plus")
            } else {
                Label("Attached", systemImage: "link")
            }
        }
        .font(.kit(.regular, 14, relativeTo: .subheadline))
        .foregroundStyle(.secondary)
    }
}
