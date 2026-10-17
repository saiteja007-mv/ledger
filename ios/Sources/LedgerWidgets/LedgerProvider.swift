import SwiftUI
import WidgetKit

struct LedgerEntry: TimelineEntry {
    let date: Date
    /// nil when the ledger couldn't be reached: the widgets say so instead of showing old numbers.
    let snapshot: WidgetSnapshot?
}

/// One provider for all three widgets: a single fetch of summary, limits and recent rows, so they agree.
/// A failed fetch is an entry with no snapshot, retried sooner than a good one.
struct LedgerProvider: TimelineProvider {
    func placeholder(in context: Context) -> LedgerEntry {
        LedgerEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (LedgerEntry) -> Void) {
        // The gallery wants an answer at once, not a 15 s fetch that fails with Tailscale off.
        if context.isPreview {
            completion(LedgerEntry(date: .now, snapshot: .sample))
            return
        }
        Task {
            completion(LedgerEntry(date: .now, snapshot: await WidgetClient.snapshot()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<LedgerEntry>) -> Void) {
        Task {
            let snapshot = await WidgetClient.snapshot()
            let entry = LedgerEntry(date: .now, snapshot: snapshot)
            let next = entry.date.addingTimeInterval(snapshot == nil ? 10 * 60 : 30 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}
