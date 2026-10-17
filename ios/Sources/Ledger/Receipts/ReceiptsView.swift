import SwiftUI

/// Every receipt the ledger holds, newest first, drawn as the receipt itself: the itemised receipts assistants
/// wrote out and the photos read on the server alike. Add one with the camera or from Photos.
struct ReceiptsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var receipts: Loadable<[Receipt]> = .loading
    @State private var isAdding = false

    var body: some View {
        KitScreen("Receipts", showsBack: true, trailing: { addButton }) {
            LoadableView(state: receipts, retry: load) { receipts in
                ScrollView {
                    LazyVStack(spacing: 22) {
                        if receipts.isEmpty {
                            ContentUnavailableView("No Receipts", systemImage: "receipt",
                                                   description: Text("Photograph a receipt to keep it with your spending."))
                                .padding(.top, 60)
                        }
                        ForEach(receipts) { receipt in
                            NavigationLink(value: Route.receipt(id: receipt.id)) {
                                ReceiptPaper(receipt: receipt, compact: true)
                                    .overlay(alignment: .topTrailing) { badge(receipt) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, KitMetrics.margin + 6)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
                .refreshable { await load() }
            }
        }
        .sheet(isPresented: $isAdding) {
            AddReceiptView(onUploaded: show)
        }
        .task(id: store.revision) {
            await load()
        }
    }

    /// Whether there's a photo behind it, and whether it's still being read.
    @ViewBuilder
    private func badge(_ receipt: Receipt) -> some View {
        if receipt.isReading {
            ProgressView().controlSize(.small).padding(10)
        } else if receipt.hasImage == true {
            Image(systemName: "photo")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(KitColor.accent.color, in: .circle)
                .padding(8)
                .accessibilityLabel("Has a photo")
        }
    }

    private var addButton: some View {
        KitBarButton(icon: .plus, label: "Add Receipt", action: add)
    }

    private func add() {
        isAdding = true
    }

    /// Opens the new receipt so you can watch it being read.
    private func show(_ id: Int) {
        navigator.morePath.append(.receipt(id: id))
    }

    private func load() async {
        let result = await Loadable.capture { try await LedgerAPI.receipts() }
        guard !Task.isCancelled else { return }
        receipts = result
    }
}
