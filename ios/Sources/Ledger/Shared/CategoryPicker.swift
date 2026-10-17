import SwiftUI

/// Pick a category, or type a new one. Categories have no table on the server: a new one
/// becomes real the moment it is assigned to a row.
struct CategoryPicker: View {
    let current: String?
    /// Extra names listed first, such as "Total" for budgets.
    var pinned: [String] = []
    let onPick: (String) -> Void

    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The ledger's spending categories, each once, A to Z: no account names or bookkeeping labels.
    private var matches: [String] {
        let accounts = Set(store.accounts.map(\.name))
        let categories = CategoryName.unique(store.categories)
            .filter { !pinned.contains($0) && CategoryName.isSpendingCategory($0, accountNames: accounts) }
            .sorted { CategoryName.display($0).localizedStandardCompare(CategoryName.display($1)) == .orderedAscending }
        let all = pinned + categories
        return trimmed.isEmpty ? all : all.filter { CategoryName.display($0).localizedStandardContains(trimmed) }
    }

    var body: some View {
        KitScreen(String(localized: "Category"), showsBack: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Search or add a category", text: $text)
                        .submitLabel(.done)
                        .onSubmit(useTyped)
                        .kitUnderlinedField()
                    if !trimmed.isEmpty, !matches.contains(where: { CategoryName.display($0).caseInsensitiveCompare(trimmed) == .orderedSame }) {
                        Button("Add “\(trimmed)”", systemImage: "plus", action: useTyped)
                            .font(.kitBodyMedium)
                            .foregroundStyle(KitColor.accent.color)
                    }
                    ForEach(matches, id: \.self) { name in
                        CategoryChoiceRow(name: name, isCurrent: name == current, pick: pick)
                    }
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .lockCover()
    }

    private func useTyped() {
        guard !trimmed.isEmpty else { return }
        pick(trimmed)
    }

    private func pick(_ name: String) {
        onPick(name)
        dismiss()
    }
}
