import SwiftUI

/// Where the data comes from, and how much of it there is.
struct AboutFooter: View {
    let status: LedgerStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let status {
                Text("^[\(status.transactions) transaction](inflect: true) · ^[\(status.accounts) account](inflect: true) · ^[\(status.receipts) receipt](inflect: true)")
            }
            Text("Your own Ledger API, over Tailscale only.")
        }
    }
}
