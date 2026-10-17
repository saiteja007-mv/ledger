import SwiftUI

/// Rows an assistant or a bank alert wrote that you haven't confirmed. Check them before trusting a total.
struct ReviewView: View {
    @Environment(LedgerStore.self) private var store
    @State private var queue: Loadable<[LedgerTransaction]> = .loading
    @State private var suggestions: [Int: CategorySuggestion] = [:]
    @State private var pendingVoid: LedgerTransaction?
    @State private var isConfirmingAll = false
    @State private var actionError: String?

    var body: some View {
        KitScreen("Review", showsBack: true, trailing: { markAllButton }) {
            LoadableView(state: queue, retry: load) { queue in
                List {
                    Section {
                        ForEach(queue) { transaction in
                            NavigationLink(value: Route.transaction(transaction)) {
                                ReviewRow(transaction: transaction, suggestion: suggestions[transaction.id], apply: apply)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Reviewed", systemImage: "checkmark") {
                                    markReviewed([transaction.id])
                                }
                                .tint(Theme.moneyIn)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Void", systemImage: "trash", role: .destructive) {
                                    pendingVoid = transaction
                                }
                            }
                        }
                    } footer: {
                        if !queue.isEmpty {
                            Text("Swipe right when a row is right, left to void a duplicate. A suggested category is only applied when you tap it.")
                        }
                    }
                    .kitRows()
                }
                .kitList()
                .overlay {
                    if queue.isEmpty {
                        ContentUnavailableView("All Reviewed", systemImage: "checkmark.seal",
                                               description: Text("Nothing is waiting for you."))
                    }
                }
                .refreshable { await load() }
            }
        }
        .confirmationDialog("Mark all \(queue.value?.count ?? 0) rows reviewed?", isPresented: $isConfirmingAll, titleVisibility: .visible) {
            Button("Mark All Reviewed", action: markAllReviewed)
        } message: {
            Text("Only do this when you've checked every row.")
        }
        .confirmationDialog("Void this transaction?", item: $pendingVoid, titleVisibility: .visible) { transaction in
            Button("Void", role: .destructive) {
                void(transaction)
            }
        } message: { transaction in
            Text("\(transaction.title), \(Money.text(transaction.amountCents, currency: transaction.currency)). It disappears from every total; the row is kept and audited.")
        }
        .alert("Couldn't Save", item: $actionError) { _ in
        } message: { message in
            Text(message)
        }
        .task(id: store.revision) {
            await load()
        }
    }

    /// Only when there's more than one row to confirm.
    @ViewBuilder
    private var markAllButton: some View {
        if let count = queue.value?.count, count > 1 {
            KitBarButton(icon: .checkmark, label: "Mark All Reviewed", action: confirmAll)
        }
    }

    private func load() async {
        async let queue = Loadable.capture { try await LedgerAPI.reviewQueue() }
        async let suggestions = Loadable.capture { try await LedgerAPI.suggestions() }
        let results = await (queue, suggestions)
        guard !Task.isCancelled else { return }
        self.queue = results.0
        self.suggestions = Dictionary((results.1.value ?? []).map { ($0.id, $0) }) { first, _ in first }
    }

    private func confirmAll() {
        isConfirmingAll = true
    }

    private func markAllReviewed() {
        markReviewed(queue.value?.map(\.id) ?? [])
    }

    private func markReviewed(_ ids: [Int]) {
        Task { await perform { try await LedgerAPI.markReviewed(ids) } }
    }

    private func apply(_ suggestion: CategorySuggestion) {
        Task { await perform { _ = try await LedgerAPI.setCategory(id: suggestion.id, category: suggestion.category) } }
    }

    private func void(_ transaction: LedgerTransaction) {
        Task { await perform { try await LedgerAPI.void(id: transaction.id, reason: "voided from the review queue in Ledger for iOS") } }
    }

    private func perform(_ action: () async throws -> Void) async {
        do {
            try await action()
            store.didChange()
        } catch {
            actionError = LedgerError(error).message
        }
    }
}
