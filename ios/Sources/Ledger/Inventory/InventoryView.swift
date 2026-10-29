import SwiftUI

/// What is probably in the house, estimated from receipts: running low first, then in stock, used up and
/// still learning, with the items that aren't followed folded away at the end. Tap an item for its details;
/// "Used up" teaches the estimate how fast an item goes.
struct InventoryView: View {
    @Environment(LedgerStore.self) private var store
    @State private var items: Loadable<[InventoryItem]> = .loading
    @State private var showsNotTracked = false
    @State private var actionError: String?

    var body: some View {
        KitScreen("Inventory", showsBack: true) {
            LoadableView(state: items, retry: load) { items in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(InventorySection.groups(items), id: \.section) { group in
                            InventorySectionHeader(
                                section: group.section, count: group.items.count,
                                isExpanded: group.section == .notTracked ? showsNotTracked : nil,
                                toggle: toggleNotTracked)
                                .padding(.top, 8)
                            if group.section != .notTracked || showsNotTracked {
                                ForEach(group.items) { item in
                                    InventoryRow(item: item, markUsedUp: markUsedUp)
                                }
                            }
                        }
                        if items.isEmpty {
                            ContentUnavailableView(
                                "Nothing Here Yet", systemImage: "cart",
                                description: Text("Items you buy more than once show up here."))
                                .padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, KitMetrics.margin)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .refreshable { await load() }
            }
        }
        .alert("Couldn't Save", item: $actionError) { _ in
        } message: { message in
            Text(message)
        }
        .task(id: store.revision) {
            await load()
        }
    }

    private func load() async {
        let result = await Loadable.capture { try await LedgerAPI.inventory(includeUntracked: true) }
        guard !Task.isCancelled else { return }
        items = result
    }

    private func toggleNotTracked() {
        showsNotTracked.toggle()
    }

    private func markUsedUp(_ item: InventoryItem) {
        Task { await perform { try await LedgerAPI.markUsedUp(item) } }
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
