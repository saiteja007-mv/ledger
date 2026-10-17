import SwiftUI

/// One account: its balance now, the reported balances behind it, a reconcile check and its recent rows.
struct AccountDetailView: View {
    let account: AccountBalance

    @Environment(LedgerStore.self) private var store
    @State private var snapshots: Loadable<[BalanceSnapshot]> = .loading
    @State private var recent: Loadable<[LedgerTransaction]> = .loading
    @State private var isRecording = false

    /// The live row for this account, so a recorded balance shows without leaving the screen.
    private var current: AccountBalance {
        store.accounts.first { $0.id == account.id } ?? account
    }

    var body: some View {
        KitScreen(account.name, showsBack: true) {
            List {
            Section {
                AccountBalanceHeader(account: current)
                Button("Record Balance", systemImage: "square.and.pencil", action: startRecording)
            } footer: {
                Text("A balance from your bank's app or statement anchors this account. Cards: enter what you owe.")
            }
            .kitRows()

            Section {
                switch snapshots {
                case .loading:
                    ProgressView()
                case .failed(let error):
                    InlineError(error: error)
                case .loaded(let snapshots) where snapshots.isEmpty:
                    Text("None yet.")
                        .foregroundStyle(.secondary)
                case .loaded(let snapshots):
                    ForEach(snapshots) { snapshot in
                        LabeledContent(LedgerDate.display(snapshot.asOfDate)) {
                            Text(Money.text(snapshot.balanceCents, currency: snapshot.currency)).monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("Reported balances").font(.kitSubtitle).textCase(nil)
            }
            .kitRows()

            if let snapshots = snapshots.value, snapshots.count >= 2 {
                ReconcileSection(account: account.name, dates: snapshots.map(\.asOfDate).sorted())
            }

            Section {
                switch recent {
                case .loading:
                    ProgressView()
                case .failed(let error):
                    InlineError(error: error)
                case .loaded(let transactions) where transactions.isEmpty:
                    Text("No transactions.")
                        .foregroundStyle(.secondary)
                case .loaded(let transactions):
                    ForEach(transactions) { transaction in
                        NavigationLink(value: Route.transaction(transaction)) {
                            TransactionRow(transaction: transaction)
                        }
                    }
                }
            } header: {
                Text("Recent transactions").font(.kitSubtitle).textCase(nil)
            }
            .kitRows()
            }
            .kitList()
        }
        .sheet(isPresented: $isRecording) {
            RecordBalanceView(account: current)
        }
        .refreshable { await load() }
        .task(id: store.revision) {
            await load()
        }
    }

    private func startRecording() {
        isRecording = true
    }

    private func load() async {
        let name = account.name
        async let snapshots = Loadable.capture { try await LedgerAPI.balances(account: name) }
        async let recent = Loadable.capture { try await LedgerAPI.transactions(account: name) }
        let results = await (snapshots, recent)
        guard !Task.isCancelled else { return }
        self.snapshots = results.0
        self.recent = results.1
    }
}
