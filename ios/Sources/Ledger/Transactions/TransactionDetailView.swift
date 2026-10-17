import SwiftUI

/// One transaction, as the kit draws it: the merchant's avatar, name, category pill and date over the
/// amount; then the account's remainder, six months of that category, and the actions. The three edits the
/// ledger allows on a row (category, reviewed, void) are the action rows. Amount, date, account and type
/// are the row's identity, so they are fixed: a wrong one is voided and logged again.
struct TransactionDetailView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var transaction: LedgerTransaction
    @State private var receipts: Loadable<[Receipt]> = .loading
    @State private var months: Loadable<[AnalysisBucket]> = .loading
    @State private var isPickingCategory = false
    @State private var isConfirmingVoid = false
    @State private var isWorking = false
    @State private var actionError: String?

    init(transaction: LedgerTransaction) {
        _transaction = State(initialValue: transaction)
    }

    private var account: AccountBalance? {
        store.accounts.first { $0.name == transaction.account }
    }

    /// For a transfer leg: the accounts the money moved between.
    private var route: TransferRoute? {
        TransferRoute(transaction, accountNames: store.accounts.map(\.name))
    }

    var body: some View {
        KitScreen(showsBack: true, hero: { hero }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    remainder
                    sixMonths
                    actions
                    receiptRows
                    details
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 22)
                .padding(.bottom, 28)
            }
        }
        .disabled(isWorking)
        .confirmationDialog("Void this transaction?", isPresented: $isConfirmingVoid, titleVisibility: .visible) {
            Button("Void", role: .destructive, action: voidTransaction)
        } message: {
            Text("It disappears from every total. The row is kept and the change is audited.")
        }
        .sheet(isPresented: $isPickingCategory) {
            CategoryPicker(current: transaction.category, onPick: setCategory)
        }
        .alert("Couldn't Save", item: $actionError) { _ in
        } message: { message in
            Text(message)
        }
        .task {
            async let receipts: Void = loadReceipts()
            async let months: Void = loadMonths()
            _ = await (receipts, months)
        }
    }

    // MARK: Header

    private var hero: some View {
        VStack(spacing: 6) {
            if transaction.direction.isTransfer {
                KitAvatar(category: transaction.title, isTransfer: true, size: 72)
            } else {
                KitAvatar(category: transaction.category ?? transaction.title, merchant: transaction.merchant, size: 72)
            }
            Text(transaction.title).font(.kitBodyMedium).lineLimit(1)
            if transaction.direction.isTransfer {
                // A transfer has no category: say which accounts it moved money between instead.
                Text(route.map { "\($0.from) → \($0.to)" } ?? String(localized: "Transfer"))
                    .font(.kitSmallMedium)
                    .foregroundStyle(KitColor.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(KitColor.black.opacity(0.92), in: .capsule)
            } else {
                Button(action: pickCategory) {
                    Text(transaction.category.map(CategoryName.display) ?? String(localized: "No category"))
                        .font(.kitSmallMedium)
                        .foregroundStyle(KitColor.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .background(KitColor.black.opacity(0.92), in: .capsule)
                }
                .accessibilityHint("Changes the category")
            }
            Text(LedgerDate.display(transaction.postedAt))
                .font(.kitSmall)
                .foregroundStyle(KitColor.secondary.color)
            KitAmountView(
                cents: transaction.amountCents, currency: transaction.currency, size: .hero,
                isNegative: transaction.direction.sign < 0
            )
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .foregroundStyle(KitColor.label.color)
        .padding(.top, 2)
    }

    // MARK: Body

    @ViewBuilder
    private var remainder: some View {
        if let account {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(KitColor.tintStrong.color)
                    KitIconView(icon: .dollar, height: 24, color: KitColor.accent.color)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Money.text(account.currentCents, currency: account.currency)).font(.kitBodyMedium)
                    Text(account.isLiability ? "Owed now" : "Remainder")
                        .font(.kitSmall)
                        .foregroundStyle(KitColor.secondary.color)
                }
                Spacer()
                Text(account.name).font(.kitSmallMedium).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var sixMonths: some View {
        if transaction.direction == .expense {
            switch months {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            case .failed:
                EmptyView()
            case .loaded(let buckets):
                VStack(alignment: .leading, spacing: 10) {
                    Text(Money.text(Int((buckets.reduce(0) { $0 + $1.expense } * 100).rounded())))
                        .font(.kit(.medium, 28, relativeTo: .title))
                    Text("Total spent for six months")
                        .font(.kitSmall)
                        .foregroundStyle(KitColor.secondary.color)
                    KitBars(
                        bars: buckets.map {
                            KitBars.Bar(id: $0.id, label: $0.label, value: $0.expense, valueText: Money.text($0.expense * 100))
                        },
                        selected: buckets.indices.last
                    )
                    .padding(.top, 8)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 2) {
            if transaction.reviewed == false {
                Button(action: markReviewed) {
                    KitMenuRow(icon: .checkmark, title: "Mark Reviewed",
                               subtitle: String(localized: "Rows an assistant or a bank alert wrote stay unreviewed until you check them"))
                }
                .buttonStyle(.plain)
            } else {
                KitMenuRow(icon: .checkmark, title: "Reviewed", showsChevron: false)
                    .foregroundStyle(KitColor.secondary.color)
            }
            if !transaction.direction.isTransfer {
                Button(action: pickCategory) {
                    KitMenuRow(icon: .categories, title: "Change category", value: transaction.category)
                }
                .buttonStyle(.plain)
            }
            Button { isConfirmingVoid = true } label: {
                KitMenuRow(icon: .issue, title: "Void Transaction", tint: KitColor.destructive.color)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var receiptRows: some View {
        if case .loaded(let receipts) = receipts, !receipts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Receipts").font(.kitSubtitle)
                ForEach(receipts) { receipt in
                    NavigationLink(value: Route.receipt(id: receipt.id)) {
                        ReceiptRow(receipt: receipt)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if case .failed(let error) = receipts {
            InlineError(error: error)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details").font(.kitSubtitle)
            detail("Account", transaction.account ?? "—")
            if let route { detail("Route", "\(route.from) → \(route.to)") }
            detail("Type", String(localized: transaction.direction.label))
            if let subcategory = transaction.subcategory { detail("Subcategory", subcategory) }
            if let note = transaction.note { detail("Note", note) }
            if transaction.isForeign, let base = transaction.baseAmount { detail("In USD", Money.dollars(base)) }
            if let source = transaction.source { detail("Logged by", source) }
            if let confidence = transaction.confidence {
                detail("Confidence", confidence.formatted(.percent.precision(.fractionLength(0))))
            }
        }
    }

    private func detail(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
            Spacer(minLength: 16)
            Text(value).font(.kitBodyMedium).multilineTextAlignment(.trailing)
        }
    }

    // MARK: Actions

    private func pickCategory() {
        isPickingCategory = true
    }

    private func loadReceipts() async {
        let id = transaction.id
        let result = await Loadable.capture {
            try await LedgerAPI.receipts(limit: 500).filter { $0.transactionId == id }
        }
        guard !Task.isCancelled else { return }
        receipts = result
    }

    /// The last six months of expenses in this transaction's category (or merchant), for the bars.
    private func loadMonths() async {
        let windows = AnalysisRange.monthly.windows()
        guard let first = windows.first else { return }
        let from = LedgerDate.day(first.start)
        let category = transaction.category
        let merchant = transaction.merchant
        let result = await Loadable.capture { try await LedgerAPI.transactions(from: from, to: nil) }
        guard !Task.isCancelled else { return }
        switch result {
        case .loading: break
        case .failed(let error): months = .failed(error)
        case .loaded(let list):
            let same = list.rows.filter { row in
                category != nil ? row.category == category : row.merchant == merchant
            }
            months = .loaded(AnalysisBucket.fill(windows, from: same))
        }
    }

    private func setCategory(_ category: String) {
        Task {
            await perform {
                let updated = try await LedgerAPI.setCategory(id: transaction.id, category: category)
                transaction.category = updated.category
            }
        }
    }

    private func markReviewed() {
        Task {
            await perform {
                try await LedgerAPI.markReviewed([transaction.id])
                transaction.reviewed = true
            }
        }
    }

    private func voidTransaction() {
        Task {
            await perform {
                try await LedgerAPI.void(id: transaction.id, reason: "voided in Ledger for iOS")
                dismiss()
            }
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await action()
            store.didChange()
        } catch {
            actionError = LedgerError(error).message
        }
    }
}
