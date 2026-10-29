import SwiftUI

/// What to buy: rows the rules and Claude suggest from the inventory, plus your own. Add an item at the top,
/// tick one when you've bought it, swipe to dismiss a suggestion or remove your own. The rules (and Claude,
/// when the server has a key) keep the list up to date on the server; "Update now" asks for a pass right away.
struct ShoppingListView: View {
    @Environment(LedgerStore.self) private var store
    @State private var shopping: Loadable<ShoppingList> = .loading
    @State private var newName = ""
    @State private var newQty = ""
    @State private var actionError: String?

    private var draft: NewShoppingItem {
        NewShoppingItem(name: newName, qty: Money.parseAmount(newQty))
    }

    /// A quantity, if typed, has to be a number above zero.
    private var canAdd: Bool {
        draft.isValid && (draft.qty != nil || newQty.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        KitScreen("Shopping List", showsBack: true) {
            LoadableView(state: shopping, retry: load) { list in
                List {
                    Section {
                        ShoppingAddRow(name: $newName, qty: $newQty, canAdd: canAdd, add: addTapped)
                    }
                    .kitRows()

                    Section {
                        ForEach(list.items) { item in
                            ShoppingRow(item: item, markBought: markBought)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if item.isOwner {
                                        Button("Remove", systemImage: "trash", role: .destructive) { remove(item) }
                                    } else {
                                        Button("Dismiss", systemImage: "xmark") { dismissSuggestion(item) }
                                    }
                                }
                        }
                        if list.items.isEmpty {
                            ContentUnavailableView(
                                "Nothing to Buy", systemImage: "cart",
                                description: Text("Items that run low show up here, or add your own above."))
                        }
                    } header: {
                        ShoppingListHeader(count: list.items.count, estimatedTotalCents: list.estimatedTotalCents)
                    }
                    .kitRows()
                }
                .kitList()
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await load() }
                .safeAreaInset(edge: .bottom) {
                    ShoppingUpdateBar(ai: list.ai, refresh: refreshTapped)
                }
            }
        }
        .alert("Couldn't Update", item: $actionError) { _ in
        } message: { message in
            Text(message)
        }
        .task(id: store.revision) {
            await load()
        }
        .task(id: shopping.value?.ai.pending ?? false) {
            await pollWhilePending()
        }
    }

    private func load() async {
        let result = await Loadable.capture { try await LedgerAPI.shoppingList() }
        guard !Task.isCancelled else { return }
        shopping = result
    }

    /// A queued pass finishes within a couple of minutes: look again every few seconds, then stop asking.
    private func pollWhilePending() async {
        guard shopping.value?.ai.pending == true else { return }
        for _ in 0..<45 {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await load()
            if shopping.value?.ai.pending != true { return }
        }
    }

    private func addTapped() {
        guard canAdd else { return }
        let draft = draft
        Task {
            if await perform({ try await LedgerAPI.updateShopping(add: [draft]) }) {
                newName = ""
                newQty = ""
            }
        }
    }

    private func markBought(_ item: ShoppingItem) {
        Task { await perform { try await LedgerAPI.updateShopping(bought: [item.id]) } }
    }

    private func dismissSuggestion(_ item: ShoppingItem) {
        Task { await perform { try await LedgerAPI.updateShopping(dismiss: [item.id]) } }
    }

    private func remove(_ item: ShoppingItem) {
        Task { await perform { try await LedgerAPI.updateShopping(remove: [item.id]) } }
    }

    private func refreshTapped() {
        Task {
            if await perform({ try await LedgerAPI.refreshShopping() }, changesLedger: false) {
                await load()
            }
        }
    }

    /// Runs one write; true when it worked. Writes that change the lists also reload every open screen.
    private func perform(_ action: () async throws -> Void, changesLedger: Bool = true) async -> Bool {
        do {
            try await action()
            if changesLedger { store.didChange() }
            return true
        } catch {
            actionError = LedgerError(error).message
            return false
        }
    }
}
