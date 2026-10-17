import SwiftUI

/// Set a monthly or weekly limit for one category, or for "Total".
struct SetBudgetView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var category: String?
    @State private var period: String
    @State private var limit: Double?
    @State private var isPickingCategory = false
    @State private var isSaving = false
    @State private var saveError: String?

    init(edit: BudgetEdit) {
        _category = State(initialValue: edit.category)
        _period = State(initialValue: edit.period)
        _limit = State(initialValue: edit.limitCents.map { Double($0) / 100 })
    }

    var body: some View {
        KitScreen(String(localized: "Budget"), showsBack: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Button(action: pickCategory) {
                        KitMenuRow(
                            icon: .categories, title: "Category",
                            value: category ?? String(localized: "Choose")
                        )
                    }
                    .buttonStyle(.plain)

                    KitSegmented(
                        selection: $period,
                        options: [(value: "monthly", title: String(localized: "Monthly")),
                                  (value: "weekly", title: String(localized: "Weekly"))]
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Limit (USD)").font(.kitSmall).foregroundStyle(KitColor.secondary.color)
                        AmountField(title: "0.00", value: $limit)
                            .font(.kit(.medium, 32, relativeTo: .title))
                            .kitUnderlinedField()
                    }

                    Text("“Total” is the overall limit across all spending.")
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
                .disabled(category == nil || (limit ?? 0) <= 0 || isSaving)
                .padding(.horizontal, KitMetrics.margin)
                .padding(.vertical, 8)
                .background(KitColor.background.color)
        }
        .sheet(isPresented: $isPickingCategory) {
            CategoryPicker(current: category, pinned: ["Total"], onPick: setCategory)
        }
        .alert("Couldn't Save", item: $saveError) { _ in
        } message: { message in
            Text(message)
        }
        .lockCover()
    }

    private func pickCategory() {
        isPickingCategory = true
    }

    private func setCategory(_ name: String) {
        category = name
    }

    private func save() {
        Task { await performSave() }
    }

    private func performSave() async {
        guard let category, let limit else { return }
        isSaving = true
        defer { isSaving = false }
        do throws(LedgerError) {
            try await LedgerAPI.setBudget(category: category, period: period, limitCents: Int((limit * 100).rounded()))
            store.didChange()
            dismiss()
        } catch {
            saveError = error.message
        }
    }
}
