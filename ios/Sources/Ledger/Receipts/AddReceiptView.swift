import PhotosUI
import SwiftUI

/// Take or choose a receipt photo, optionally say what it is, and upload it. Blank fields are
/// read off the photo on your server, which then attaches the receipt to a matching transaction.
struct AddReceiptView: View {
    /// Called with the new receipt's id after a successful upload.
    let onUploaded: (Int) -> Void

    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var photo: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var merchant = ""
    @State private var total: Double?
    @State private var knowsDate = false
    @State private var purchasedAt = Date.now
    @State private var isUploading = false
    @State private var uploadError: String?

    var body: some View {
        KitScreen(String(localized: "Add Receipt"), showsBack: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: Theme.photoMaxHeight)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .accessibilityLabel("Receipt photo")
                    }
                    VStack(spacing: 2) {
                        if CameraPicker.isAvailable {
                            Button(action: openCamera) {
                                KitMenuRow(icon: .card, title: photo == nil ? "Take Photo" : "Retake Photo")
                            }
                            .buttonStyle(.plain)
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Choose from Photos", systemImage: "photo.on.rectangle")
                                .font(.kitBodyMedium)
                                .foregroundStyle(KitColor.label.color)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("Merchant (optional)", text: $merchant)
                        .textInputAutocapitalization(.words)
                        .kitUnderlinedField()
                    AmountField(title: "Total (optional)", value: $total)
                        .kitUnderlinedField()
                    Toggle("I know the date", isOn: $knowsDate)
                        .font(.kitBodyMedium)
                    if knowsDate {
                        DatePicker("Date", selection: $purchasedAt, displayedComponents: .date)
                            .font(.kitBodyMedium)
                    }
                    Text("Leave these blank and Ledger reads the merchant, items, tax and total off the photo.")
                        .font(.kitSmall)
                        .foregroundStyle(KitColor.secondary.color)
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if isUploading {
                    ProgressView().frame(minHeight: 56)
                } else {
                    Button("Upload", action: upload)
                        .buttonStyle(KitPrimaryButtonStyle())
                        .disabled(photo == nil)
                }
            }
            .padding(.horizontal, KitMetrics.margin)
            .padding(.vertical, 8)
            .background(KitColor.background.color)
        }
        .disabled(isUploading)
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(onFinish: cameraFinished)
                .ignoresSafeArea()
        }
        .task(id: pickerItem) {
            await loadPickedPhoto()
        }
        .alert("Couldn't Upload", item: $uploadError) { _ in
        } message: { message in
            Text(message)
        }
        .lockCover()
    }

    private func openCamera() {
        isShowingCamera = true
    }

    private func cameraFinished(_ image: UIImage?) {
        isShowingCamera = false
        if let image { photo = image }
    }

    private func loadPickedPhoto() async {
        guard let pickerItem else { return }
        if let data = try? await pickerItem.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            photo = image
        } else {
            uploadError = String(localized: "That photo couldn't be opened.")
        }
    }

    private func upload() {
        Task { await performUpload() }
    }

    private func performUpload() async {
        guard let photo, let jpeg = ReceiptPhoto.jpeg(from: photo) else {
            uploadError = String(localized: "That photo couldn't be prepared for upload.")
            return
        }
        isUploading = true
        defer { isUploading = false }
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let (total, date) = (total, knowsDate ? purchasedAt : nil)
        do throws(LedgerError) {
            let result = try await LedgerAPI.uploadReceipt(
                jpeg: jpeg, merchant: name.isEmpty ? nil : name, total: total, purchasedAt: date, transactionID: nil)
            store.didChange()
            dismiss()
            onUploaded(result.id)
        } catch {
            uploadError = error.message
        }
    }
}
