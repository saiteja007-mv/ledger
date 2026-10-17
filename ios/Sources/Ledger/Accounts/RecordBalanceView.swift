import SwiftUI

/// Record what the bank says an account holds (or what a card owes) on a date.
struct RecordBalanceView: View {
    let account: AccountBalance

    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var amount: Double?
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        KitScreen(account.name, showsBack: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.isLiability ? "Amount owed" : "Balance")
                            .font(.kitSmall)
                            .foregroundStyle(KitColor.secondary.color)
                        AmountField(title: "0.00", value: $amount)
                            .font(.kit(.medium, 40, relativeTo: .largeTitle))
                            .kitUnderlinedField()
                    }
                    HStack(spacing: 16) {
                        KitIconView(icon: .calendar, height: 24, color: KitColor.label.color).frame(width: 28)
                        Text("As of").font(.kitBodyMedium)
                        Spacer()
                        DatePicker("As of", selection: $date, displayedComponents: .date).labelsHidden()
                    }
                    Text("In \(account.currency). One balance per day; recording the same day again replaces it.")
                        .font(.kitSmall)
                        .foregroundStyle(KitColor.secondary.color)
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Save", action: save)
                .buttonStyle(KitPrimaryButtonStyle())
                .disabled(amount == nil || isSaving)
                .padding(.horizontal, KitMetrics.margin)
                .padding(.vertical, 8)
                .background(KitColor.background.color)
        }
        .alert("Couldn't Save", item: $saveError) { _ in
        } message: { message in
            Text(message)
        }
        .lockCover()
    }

    private func save() {
        Task { await performSave() }
    }

    private func performSave() async {
        guard let amount else { return }
        isSaving = true
        defer { isSaving = false }
        do throws(LedgerError) {
            try await LedgerAPI.recordBalance(account: account.name, date: date, cents: Int((amount * 100).rounded()), currency: account.currency)
            store.didChange()
            dismiss()
        } catch {
            saveError = error.message
        }
    }
}
