import SwiftUI

/// One item: its estimate and figures, Used up and Track / Don't track, then the price over time and every
/// purchase (the same chart and rows as Item Prices).
struct InventoryItemView: View {
    let item: InventoryItem

    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var points: Loadable<[PricePoint]> = .loading
    @State private var actionError: String?

    var body: some View {
        KitScreen("Inventory", showsBack: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    InventoryItemHeader(item: item)

                    InventoryItemActions(
                        item: item, usedUp: usedUpTapped, track: trackTapped, stopTracking: stopTrackingTapped)

                    LoadableView(state: points, retry: load) { points in
                        InventoryPurchases(points: points, unit: item.unit)
                    }
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .refreshable { await load() }
        }
        .alert("Couldn't Save", item: $actionError) { _ in
        } message: { message in
            Text(message)
        }
        .task {
            await load()
        }
    }

    private func load() async {
        let item = item
        let result = await Loadable.capture { try await LedgerAPI.priceHistory(for: item) }
        guard !Task.isCancelled else { return }
        points = result
    }

    private func usedUpTapped() {
        let item = item
        Task { await perform { try await LedgerAPI.markUsedUp(item) } }
    }

    private func trackTapped() {
        let item = item
        Task { await perform { try await LedgerAPI.setTracking(item, tracked: true) } }
    }

    private func stopTrackingTapped() {
        let item = item
        Task { await perform { try await LedgerAPI.setTracking(item, tracked: false) } }
    }

    /// The item's status is stale after a change, so go back to the list, which reloads.
    private func perform(_ action: () async throws -> Void) async {
        do {
            try await action()
            store.didChange()
            dismiss()
        } catch {
            actionError = LedgerError(error).message
        }
    }
}
