import PhotosUI
import SwiftUI

/// Log Spending, drawn as the kit's payment entry: the amount big in the middle, a comment line, the
/// account and category as rows, an optional receipt photo, and a black Confirm. The amount comes first; the
/// rest has sensible defaults. A Siri or Shortcuts link can fill any of it in (`prefill`).
struct AddTransactionView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The account you logged with last time. An account name, not a secret.
    @AppStorage("lastAccount") private var lastAccount = ""
    @State private var draft: NewTransaction
    @State private var amountText: String
    @State private var isPickingCategory = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedCount = 0
    /// A receipt to attach: uploaded with the transaction's id once it's saved, then read into items.
    @State private var receipt: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @FocusState private var amountFocused: Bool

    init(prefill: NewTransaction? = nil) {
        let draft = prefill ?? NewTransaction()
        _draft = State(initialValue: draft)
        _amountText = State(initialValue: draft.amount.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? "")
    }

    private enum Kind: Hashable {
        case expense, income, transfer
    }

    private var kind: Binding<Kind> {
        Binding {
            switch draft.direction {
            case .expense: .expense
            case .income: .income
            case .transferOut, .transferIn: .transfer
            }
        } set: { kind in
            switch kind {
            case .expense: draft.direction = .expense
            case .income: draft.direction = .income
            case .transfer: draft.direction = .transferOut
            }
        }
    }

    var body: some View {
        KitScreen(String(localized: "Log Spending"), showsBack: true) {
            ScrollView {
                VStack(spacing: 22) {
                    KitSegmented(
                        selection: kind,
                        options: [(value: Kind.expense, title: String(localized: "Expense")),
                                  (value: Kind.income, title: String(localized: "Income")),
                                  (value: Kind.transfer, title: String(localized: "Transfer"))]
                    )

                    amount

                    TextField("Merchant or who", text: $draft.merchant)
                        .textInputAutocapitalization(.words)
                        .kitUnderlinedField()
                    TextField("Add a comment for this transaction", text: $draft.note, axis: .vertical)
                        .lineLimit(1...4)
                        .kitUnderlinedField()

                    VStack(spacing: 2) {
                        row(icon: .categories, title: "Category", value: draft.category ?? String(localized: "None")) {
                            isPickingCategory = true
                        }
                        accountRow(title: draft.direction.isTransfer ? "From account" : "Account", selection: $draft.account)
                        if draft.direction.isTransfer {
                            accountRow(title: "To account", selection: $draft.counterAccount)
                            Picker("Direction", selection: $draft.direction) {
                                Text("Money out").tag(Direction.transferOut)
                                Text("Money in").tag(Direction.transferIn)
                            }
                            .pickerStyle(.segmented)
                            .padding(.vertical, 8)
                        }
                        HStack(spacing: 16) {
                            KitIconView(icon: .calendar, height: 24, color: KitColor.label.color).frame(width: 28)
                            Text("When").font(.kitBodyMedium)
                            Spacer()
                            DatePicker("When", selection: $draft.date).labelsHidden()
                        }
                        .frame(minHeight: 44)
                        HStack(spacing: 16) {
                            KitIconView(icon: .dollar, height: 24, color: KitColor.label.color).frame(width: 28)
                            Text("Currency").font(.kitBodyMedium)
                            Spacer()
                            TextField("USD", text: $draft.currency)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .font(.kitBody)
                                .frame(maxWidth: 90)
                        }
                        .frame(minHeight: 44)
                    }
                    Text("Other currencies are converted to USD at that day's rate.")
                        .font(.kitSmall)
                        .foregroundStyle(KitColor.secondary.color)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    receiptSection
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if isSaving {
                    ProgressView().frame(minHeight: 56)
                } else {
                    Button("Confirm", action: save)
                        .buttonStyle(KitPrimaryButtonStyle())
                        .disabled(!draft.isValid)
                }
            }
            .padding(.horizontal, KitMetrics.margin)
            .padding(.vertical, 8)
            .background(KitColor.background.color)
        }
        .disabled(isSaving)
        .sheet(isPresented: $isPickingCategory) {
            CategoryPicker(current: draft.category, onPick: setCategory)
        }
        .alert("Couldn't Save", item: $saveError) { _ in
        } message: { message in
            Text(message)
        }
        .sensoryFeedback(.success, trigger: savedCount)
        .onChange(of: draft.account) { _, name in
            accountChanged(to: name)
        }
        .onAppear(perform: focusAmount)
        // The account list may arrive after the sheet opens.
        .task(id: store.accounts.count) {
            chooseDefaultAccount()
        }
        .task(id: pickerItem) {
            await loadPicked()
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                isShowingCamera = false
                if let image { receipt = image }
            }
            .ignoresSafeArea()
        }
        .lockCover()
    }

    // MARK: Receipt

    private var receiptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Receipt").font(.kitSubtitle)
            if let receipt {
                HStack(spacing: 14) {
                    Image(uiImage: receipt)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attached").font(.kitBodyMedium)
                        Text("It's read into items after you confirm.")
                            .font(.kitSmall)
                            .foregroundStyle(KitColor.secondary.color)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) {
                        self.receipt = nil
                        pickerItem = nil
                    }
                    .font(.kitSmallMedium)
                }
            } else {
                HStack(spacing: 10) {
                    if CameraPicker.isAvailable {
                        Button { isShowingCamera = true } label: {
                            Label("Take photo", systemImage: "camera.fill").frame(maxWidth: .infinity)
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose photo", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(KitColor.accent.color)
                .font(.kitSmallMedium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadPicked() async {
        guard let pickerItem else { return }
        if let data = try? await pickerItem.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            receipt = image
        }
    }

    // MARK: Pieces

    private var amount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("$").font(.kit(.medium, 28, relativeTo: .title))
            // Text, not TextField(value:format:), so Confirm enables as you type (see AmountField).
            TextField("0.00", text: $amountText)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .font(.kitHeadingXL)
                .multilineTextAlignment(.leading)
                .fixedSize()
                .onChange(of: amountText) { _, text in
                    draft.amount = Money.parseAmount(text)
                }
        }
        .foregroundStyle(KitColor.label.color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func row(icon: KitIcon, title: LocalizedStringKey, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            KitMenuRow(icon: icon, title: title, value: value)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func accountRow(title: LocalizedStringKey, selection: Binding<String>) -> some View {
        if store.accounts.isEmpty {
            HStack(spacing: 16) {
                KitIconView(icon: .card, height: 24, color: KitColor.label.color).frame(width: 28)
                TextField(title, text: selection)
                    .textInputAutocapitalization(.words)
                    .font(.kitBodyMedium)
            }
            .frame(minHeight: 44)
        } else {
            Menu {
                Picker("Account", selection: selection) {
                    if !store.accounts.contains(where: { $0.name == selection.wrappedValue }) {
                        Text("Choose").tag(selection.wrappedValue)
                    }
                    ForEach(store.accounts) { account in
                        Text(account.name).tag(account.name)
                    }
                }
            } label: {
                KitMenuRow(
                    icon: .card, title: title,
                    value: selection.wrappedValue.isEmpty ? String(localized: "Choose") : selection.wrappedValue
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    private func focusAmount() {
        amountFocused = true
    }

    private func chooseDefaultAccount() {
        let names = store.accounts.map(\.name)
        // A link may name the account loosely ("checking 1234"): use the ledger's spelling.
        if let match = names.first(where: { $0.caseInsensitiveCompare(draft.account) == .orderedSame }) {
            draft.account = match
        }
        guard draft.account.isEmpty else { return }
        draft.account = names.contains(lastAccount) ? lastAccount : names.first ?? ""
    }

    /// New rows default to the account's own currency.
    private func accountChanged(to name: String) {
        if let account = store.accounts.first(where: { $0.name == name }) {
            draft.currency = account.currency
        }
    }

    private func setCategory(_ category: String) {
        draft.category = category
    }

    private func save() {
        Task { await performSave() }
    }

    private func performSave() async {
        isSaving = true
        defer { isSaving = false }
        let draft = draft
        do throws(LedgerError) {
            let id = try await LedgerAPI.add(draft)
            lastAccount = draft.account
            if let receipt, let jpeg = ReceiptPhoto.jpeg(from: receipt) {
                // Saving again would update the same row (upsert), so a failed upload can simply be retried.
                let merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
                do throws(LedgerError) {
                    _ = try await LedgerAPI.uploadReceipt(
                        jpeg: jpeg, merchant: merchant.isEmpty ? nil : merchant, total: draft.amount,
                        purchasedAt: draft.date, transactionID: id)
                } catch {
                    store.didChange()
                    saveError = String(localized: "Logged, but the receipt didn't upload: \(error.message) Tap Confirm to try the receipt again.")
                    return
                }
            }
            savedCount += 1
            store.didChange()
            dismiss()
        } catch {
            saveError = error.message
        }
    }
}
