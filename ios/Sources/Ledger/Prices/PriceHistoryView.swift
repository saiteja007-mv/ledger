import SwiftUI

/// One item: what it costs now per unit and how that moved, its lowest / average / highest, the price over
/// time, and every purchase with the store's logo.
struct PriceHistoryView: View {
    let item: PriceItem

    @State private var points: Loadable<[PricePoint]> = .loading

    var body: some View {
        KitScreen(String(localized: "Item Prices"), showsBack: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    stats
                    LoadableView(state: points, retry: load) { points in
                        VStack(alignment: .leading, spacing: 22) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Price per \(item.unit)").font(.kitSubtitle)
                                PriceChart(points: points, unit: item.unit)
                            }
                            .padding(16)
                            .background(KitColor.surface.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                            VStack(alignment: .leading, spacing: 14) {
                                Text("Purchases").font(.kitSubtitle)
                                ForEach(points.reversed()) { point in
                                    PricePointRow(point: point, unit: item.unit)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .refreshable { await load() }
        }
        .task {
            await load()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name.capitalized).font(.kit(.medium, 24, relativeTo: .title2)).lineLimit(3)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let last = item.lastCents {
                    Text(Money.text(last)).font(.kit(.medium, 36, relativeTo: .largeTitle)).monospacedDigit()
                    Text("per \(item.unit)").font(.kitSmall).foregroundStyle(KitColor.secondary.color)
                }
                if let change = item.changePct, change != 0 {
                    PriceChangeLabel(changePct: change)
                }
            }
            Text(lastBought).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
        }
        .foregroundStyle(KitColor.label.color)
    }

    private var lastBought: String {
        let times = String(localized: "Bought \(item.purchases)× at \(item.merchants) stores")
        guard let at = item.lastAt else { return times }
        let when = LedgerDate.display(at)
        return item.lastMerchant.map { String(localized: "Last \(when) at \($0) · \(times)") } ?? "\(when) · \(times)"
    }

    private var stats: some View {
        HStack(spacing: 10) {
            stat(String(localized: "Lowest"), item.minCents, tint: KitColor.positive.color)
            stat(String(localized: "Average"), item.avgCents, tint: KitColor.accent.color)
            stat(String(localized: "Highest"), item.maxCents, tint: KitColor.destructive.color)
        }
    }

    private func stat(_ label: String, _ cents: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.kitCaption).foregroundStyle(KitColor.secondary.color)
            Text(cents.map { Money.text($0) } ?? "—").font(.kit(.medium, 17)).foregroundStyle(tint).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func load() async {
        let item = item
        let result = await Loadable.capture { try await LedgerAPI.priceHistory(for: item) }
        guard !Task.isCancelled else { return }
        points = result
    }
}
