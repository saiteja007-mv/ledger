import Charts
import SwiftUI

/// Unit price over time: a soft area under the line, a dot per purchase, the latest one larger.
struct PriceChart: View {
    let points: [PricePoint]
    let unit: String

    private var plotted: [PricePoint] {
        points.filter { $0.unitPriceCents != nil && $0.date != nil }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    var body: some View {
        if plotted.count < 2 {
            Text("A chart appears after the second purchase.")
                .font(.kitSmall)
                .foregroundStyle(KitColor.secondary.color)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            let last = plotted.last?.id
            Chart(plotted) { point in
                let date = point.date ?? .now
                let price = Double(point.unitPriceCents ?? 0) / 100
                AreaMark(x: .value("Date", date), y: .value("Price per \(unit)", price))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(colors: [KitColor.accent.color.opacity(0.28), KitColor.accent.color.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", date), y: .value("Price per \(unit)", price))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(KitColor.accent.color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                PointMark(x: .value("Date", date), y: .value("Price per \(unit)", price))
                    .foregroundStyle(KitColor.accent.color)
                    .symbolSize(point.id == last ? 90 : 30)
                    .accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(Money.text(point.unitPriceCents ?? 0)) at \(point.merchant ?? "unknown store")")
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(KitColor.separator.color)
                    AxisValueLabel {
                        if let price = value.as(Double.self) { Text(Money.dollars(price)).font(.kitCaption) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.kitCaption)
                }
            }
            .frame(height: 190)
        }
    }
}
