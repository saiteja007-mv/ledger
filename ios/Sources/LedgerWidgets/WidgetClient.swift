import Foundation

/// The widgets' own thin client for ledger-api on your server (the app's `LedgerAPI` isn't shared with the
/// extension). Tailnet only and Tailscale identity is the auth, so there's no token. Any failure is `nil`:
/// the widgets say the ledger can't be reached and never fall back to old numbers.
enum WidgetClient {
    /// The widget's own Info.plist `LedgerServerURL` (scripts/ios-config.cjs writes it): an address typed in the
    /// app doesn't reach the extension, so a widget without it shows the ledger as unreachable.
    private static let baseURL: URL? = {
        guard var text = (Bundle.main.object(forInfoDictionaryKey: "LedgerServerURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        return URL(string: text)?.appending(path: "api/tool/")
    }()

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable {
        let ok: Bool
        let result: Value?
    }

    private static func call<Value: Decodable & Sendable>(_ tool: String, _ arguments: [String: Int] = [:]) async -> Value? {
        guard let baseURL else { return nil }
        var request = URLRequest(url: baseURL.appending(path: tool), timeoutInterval: 15)
        request.httpMethod = "POST"
        // The API wants JSON and no Origin header; URLSession never adds one.
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(arguments)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(Envelope<Value>.self, from: data), envelope.ok else { return nil }
        return envelope.result
    }

    /// This month's totals, the limits and the newest rows, or nil when any of them can't be read.
    static func snapshot() async -> WidgetSnapshot? {
        async let summary: WidgetSummary? = call("spending_summary")
        async let budgets: [WidgetBudget]? = call("budget_status")
        async let rows: [WidgetTransaction]? = call("list_transactions", ["limit": 20])
        guard let summary = await summary, let budgets = await budgets, let rows = await rows else { return nil }
        return WidgetSnapshot(summary: summary, budgets: budgets, recent: rows.filter { !$0.isTransfer })
    }
}
