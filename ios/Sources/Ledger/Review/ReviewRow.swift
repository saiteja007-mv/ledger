import SwiftUI

/// A row waiting for review, who wrote it, and a one-tap suggested category when the rules have one.
struct ReviewRow: View {
    let transaction: LedgerTransaction
    let suggestion: CategorySuggestion?
    let apply: (CategorySuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TransactionRow(transaction: transaction)
            if let source = transaction.source {
                Text("From \(source)")
                    .font(.kit(.regular, 14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            }
            if let suggestion, suggestion.category != transaction.category {
                Button {
                    apply(suggestion)
                } label: {
                    Label("Use \(suggestion.category)", systemImage: "sparkles")
                        .font(.kit(.regular, 14, relativeTo: .subheadline))
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Matched “\(suggestion.rule)”")
            }
        }
    }
}
