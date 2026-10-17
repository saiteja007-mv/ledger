import SwiftUI

/// Checks that the ledger explains the change between two reported balances.
struct ReconcileSection: View {
    let account: String
    /// Reported balance dates, oldest first (at least two).
    let dates: [String]

    @State private var from = ""
    @State private var to = ""
    @State private var result: Loadable<Reconciliation>?

    var body: some View {
        Section {
            Picker("From", selection: $from) {
                ForEach(dates, id: \.self) { date in
                    Text(LedgerDate.display(date)).tag(date)
                }
            }
            Picker("To", selection: $to) {
                ForEach(dates, id: \.self) { date in
                    Text(LedgerDate.display(date)).tag(date)
                }
            }
            Button("Reconcile", systemImage: "equal.circle", action: check)
                .disabled(from.isEmpty || to <= from)

            switch result {
            case .none:
                EmptyView()
            case .loading:
                ProgressView()
            case .failed(let error):
                InlineError(error: error)
            case .loaded(let reconciliation):
                ReconciliationRows(reconciliation: reconciliation)
            }
        } header: {
            Text("Reconcile")
        } footer: {
            Text("Drift means a transaction is missing, doubled or wrong between those two balances.")
        }
        .kitRows()
        .onAppear(perform: chooseDefaults)
    }

    private func chooseDefaults() {
        guard from.isEmpty, let first = dates.first, let last = dates.last else { return }
        from = first
        to = last
    }

    private func check() {
        Task { await reconcile() }
    }

    private func reconcile() async {
        result = .loading
        let (account, from, to) = (account, from, to)
        result = await Loadable.capture { try await LedgerAPI.reconcile(account: account, from: from, to: to) }
    }
}
