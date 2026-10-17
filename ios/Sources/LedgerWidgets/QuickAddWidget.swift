import SwiftUI
import WidgetKit

/// "Log Spending": one tap opens the form. Nothing to fetch, so it never shows stale or missing numbers.
/// (An interactive widget or a Siri action would need App Intents, which xtool can't build; Siri goes through a
/// Shortcut that opens the same link with the amount and merchant filled in, see Account → Siri & Shortcuts.)
struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LedgerQuickAdd", provider: QuickAddProvider()) { _ in
            QuickAddWidgetView()
        }
        .configurationDisplayName("Log Spending")
        .description("Open Log Spending with one tap.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct QuickAddEntry: TimelineEntry {
    let date: Date
}

/// One entry, never refreshed: the widget only links into the app.
struct QuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry { QuickAddEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (QuickAddEntry) -> Void) {
        completion(QuickAddEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<QuickAddEntry>) -> Void) {
        completion(Timeline(entries: [QuickAddEntry(date: .now)], policy: .never))
    }
}

struct QuickAddWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                }
                .accessibilityLabel("Log Spending")
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Log Spending").font(.headline)
                        Text("Ledger").font(.caption2)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(WidgetPalette.hero)
                        .frame(width: 54, height: 54)
                        .background(.black, in: .circle)
                    Spacer()
                    Text("Log").font(.system(size: 24, weight: .bold))
                    Text("spending").font(.system(size: 24, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "ledger://add"))
        .containerBackground(for: .widget) {
            if family == .systemSmall { WidgetPalette.hero } else { Color.clear }
        }
    }
}
