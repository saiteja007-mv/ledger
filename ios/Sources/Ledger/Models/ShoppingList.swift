import Foundation

/// The open shopping list from the `shopping_list` tool, with the status of Claude's last pass over it.
struct ShoppingList: Decodable, Sendable {
    let items: [ShoppingItem]
    let totalCents: Int?
    let ai: AIStatus

    /// Quantity times last price over the rows that have a price; nil when none has one.
    var estimatedTotalCents: Int? {
        items.contains { $0.lastPriceCents != nil } ? totalCents : nil
    }

    /// When Claude last updated the list, whether that worked, and whether another pass is queued.
    struct AIStatus: Decodable, Hashable, Sendable {
        /// An ISO 8601 UTC time.
        let lastRunAt: String?
        /// nil when it never ran (no key file).
        let ok: Bool?
        let message: String?
        let pending: Bool

        /// The line under the list: "Updating…", "Updated by Claude 2 h ago", the server's own
        /// message when a run failed ("no API key: rules only"), or "Rules only" when there is none.
        func footer(now: Date = .now) -> String {
            if pending { return String(localized: "Updating…") }
            switch ok {
            case true?:
                guard let ranAt else { return String(localized: "Updated by Claude") }
                return String(localized: "Updated by Claude \(Self.ago(ranAt, now: now))")
            case false?:
                guard let message, !message.isEmpty else { return String(localized: "Rules only") }
                return message
            case nil:
                return String(localized: "Rules only")
            }
        }

        private var ranAt: Date? {
            guard let lastRunAt else { return nil }
            return (try? Date(lastRunAt, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                ?? (try? Date(lastRunAt, strategy: .iso8601))
        }

        private static func ago(_ date: Date, now: Date) -> String {
            let seconds = Int(now.timeIntervalSince(date))
            switch seconds {
            case ..<60: return String(localized: "just now")
            case ..<3600: return String(localized: "\(seconds / 60) min ago")
            case ..<86_400: return String(localized: "\(seconds / 3600) h ago")
            default: return String(localized: "\(seconds / 86_400) d ago")
            }
        }
    }
}
