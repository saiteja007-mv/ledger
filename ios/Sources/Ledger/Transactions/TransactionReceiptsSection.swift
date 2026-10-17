import SwiftUI

/// Receipts attached to a transaction; nothing at all when there are none.
struct TransactionReceiptsSection: View {
    let receipts: Loadable<[Receipt]>

    var body: some View {
        switch receipts {
        case .loading:
            EmptyView()
        case .failed(let error):
            Section("Receipts") { InlineError(error: error) }.kitRows()
        case .loaded(let receipts) where receipts.isEmpty:
            EmptyView()
        case .loaded(let receipts):
            Section("Receipts") {
                ForEach(receipts) { receipt in
                    NavigationLink(value: Route.receipt(id: receipt.id)) {
                        ReceiptRow(receipt: receipt)
                    }
                }
            }
            .kitRows()
        }
    }
}
