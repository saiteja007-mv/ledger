import SwiftUI

/// The latest writes against the ledger, from any client.
struct AuditView: View {
    @State private var entries: Loadable<[AuditEntry]> = .loading

    var body: some View {
        KitScreen("Audit Log", showsBack: true) {
            LoadableView(state: entries, retry: load) { entries in
                List {
                    Section {
                        ForEach(entries) { entry in
                            AuditRow(entry: entry)
                        }
                    }
                    .kitRows()
                }
                .kitList()
                .refreshable { await load() }
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        let result = await Loadable.capture { try await LedgerAPI.audit() }
        guard !Task.isCancelled else { return }
        entries = result
    }
}
