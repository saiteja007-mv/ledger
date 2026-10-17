import SwiftUI

/// Every item seen on stored receipts, most bought first: what it costs now per unit, how that moved since the
/// purchase before, and where it sits between its lowest and highest. Search, or show only what rose or fell.
struct PricesView: View {
    @State private var items: Loadable<[PriceItem]> = .loading
    @State private var query = ""
    @State private var trend = Trend.all

    enum Trend: Hashable {
        case all, rising, falling
    }

    var body: some View {
        KitScreen("Item Prices", showsBack: true) {
            VStack(spacing: 12) {
                searchField
                KitSegmented(
                    selection: $trend,
                    options: [(value: Trend.all, title: String(localized: "All")),
                              (value: Trend.rising, title: String(localized: "Rising")),
                              (value: Trend.falling, title: String(localized: "Falling"))]
                )
                LoadableView(state: items, retry: load) { items in
                    let shown = filtered(items)
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if !items.isEmpty { summary(items) }
                            ForEach(shown) { item in
                                NavigationLink(value: Route.priceHistory(item)) {
                                    PriceRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                            if shown.isEmpty {
                                ContentUnavailableView(
                                    query.isEmpty ? "No Prices Yet" : "No Matches", systemImage: "cart",
                                    description: Text(query.isEmpty
                                        ? "Prices come from the items on your receipts."
                                        : "No item matches “\(query)”."))
                                    .padding(.top, 40)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable { await load() }
                }
            }
            .padding(.horizontal, KitMetrics.margin)
            .padding(.top, 10)
        }
        .task(id: query) {
            await queryChanged()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(KitColor.secondary.color)
            TextField("Search items", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.kitBody)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(KitColor.secondary.color)
                }
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(KitColor.surface.color, in: .capsule)
    }

    private func summary(_ items: [PriceItem]) -> some View {
        let up = items.filter { ($0.changePct ?? 0) > 0 }.count
        let down = items.filter { ($0.changePct ?? 0) < 0 }.count
        return HStack(spacing: 10) {
            tile(String(items.count), String(localized: "items tracked"), tint: KitColor.accent.color)
            tile(String(up), String(localized: "cost more"), tint: KitColor.destructive.color)
            tile(String(down), String(localized: "cost less"), tint: KitColor.positive.color)
        }
        .padding(.bottom, 4)
    }

    private func tile(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.kit(.medium, 22)).foregroundStyle(tint).monospacedDigit()
            Text(label).font(.kitCaption).foregroundStyle(KitColor.secondary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func filtered(_ items: [PriceItem]) -> [PriceItem] {
        switch trend {
        case .all: items
        case .rising: items.filter { ($0.changePct ?? 0) > 0 }.sorted { ($0.changePct ?? 0) > ($1.changePct ?? 0) }
        case .falling: items.filter { ($0.changePct ?? 0) < 0 }.sorted { ($0.changePct ?? 0) < ($1.changePct ?? 0) }
        }
    }

    private func queryChanged() async {
        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(350))
        }
        guard !Task.isCancelled else { return }
        await load()
    }

    private func load() async {
        let query = query
        let result = await Loadable.capture { try await LedgerAPI.priceItems(query: query) }
        guard !Task.isCancelled else { return }
        items = result
    }
}
