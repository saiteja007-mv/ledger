import SwiftUI

/// One receipt, printed in full (items, subtotal, tax, total, how it was paid), then the original photo if
/// there is one, and its transaction. While a photo is being read on the server, this checks back every few seconds.
struct ReceiptDetailView: View {
    let id: Int

    @State private var receipt: Loadable<Receipt> = .loading
    @State private var photo: UIImage?
    @State private var isShowingPhoto = false

    var body: some View {
        KitScreen(receipt.value?.title ?? String(localized: "Receipt"), showsBack: true) {
            LoadableView(state: receipt, retry: load) { receipt in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ReceiptPaper(receipt: receipt)
                        if receipt.isReading {
                            Label("Reading the photo…", systemImage: "hourglass")
                                .font(.kitSmall)
                                .foregroundStyle(KitColor.secondary.color)
                        }
                        if let photo {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Original photo").font(.kitSubtitle)
                                Button { isShowingPhoto = true } label: {
                                    Image(uiImage: photo)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 180)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Receipt photo, full screen")
                            }
                        }
                        if let transaction = receipt.transaction {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Transaction").font(.kitSubtitle)
                                NavigationLink(value: Route.transaction(transaction)) {
                                    KitTransactionRow(transaction: transaction)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, KitMetrics.margin + 6)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
                .refreshable { await load() }
            }
        }
        .fullScreenCover(isPresented: $isShowingPhoto) {
            photoViewer
        }
        .task {
            await load()
            await loadPhoto()
            await followReading()
        }
    }

    private var photoViewer: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let photo {
                Image(uiImage: photo).resizable().scaledToFit()
            }
            Button { isShowingPhoto = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: .circle)
            }
            .padding()
            .accessibilityLabel("Close")
        }
    }

    private func load() async {
        let id = id
        let result = await Loadable.capture { try await LedgerAPI.receipt(id: id) }
        guard !Task.isCancelled else { return }
        receipt = result
    }

    private func loadPhoto() async {
        guard receipt.value?.hasImage == true else { return }
        let id = id
        let image = await Loadable.capture { try await LedgerAPI.receiptImage(id: id) }
        if let data = image.value?.data {
            photo = UIImage(data: data)
        }
    }

    /// A read takes up to a few minutes; check back until it's done or failed, then stop.
    private func followReading() async {
        for _ in 0..<80 where receipt.value?.isReading == true {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await load()
        }
    }
}
