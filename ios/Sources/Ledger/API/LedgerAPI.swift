import Foundation

/// Client for ledger-api on your server (`web/api.cjs`, contract in `docs/api.md`).
/// It's reachable only on the tailnet, and Tailscale identity is the auth, so the app holds no token.
/// Every call is `POST /api/tool/<name>` with the tool's arguments as JSON; the typed calls are in
/// `LedgerAPI+Tools.swift`. Each call throws `LedgerError`; screens show the error, never old numbers.
enum LedgerAPI {
    /// `<server>/api/tool/`, the server published with `tailscale serve --https=8448 http://127.0.0.1:8098`.
    /// With no server set every call fails as unreachable, and the app shows Connect.
    static var baseURL: URL {
        (ServerConfig.serverURL ?? URL(string: "https://server-not-set.invalid")!).appending(path: "api/tool/")
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// A fresh decoder per call: cheap, and nothing shared across tasks.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Calls one tool. Arguments that are nil are left out, which the API reads as "use the default".
    static func call<Value: Decodable & Sendable>(
        _ tool: String,
        _ arguments: [String: JSONValue?] = [:],
        timeout: TimeInterval = 15
    ) async throws(LedgerError) -> Value {
        var request = URLRequest(url: baseURL.appending(path: tool), timeoutInterval: timeout)
        request.httpMethod = "POST"
        // The API refuses any write that isn't JSON or that carries an Origin header: that's how it tells
        // this app from a web page on a tailnet device. URLSession never adds Origin.
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(JSONValue.fields(arguments))
        } catch {
            throw .rejected("That value can't be sent to the Ledger API.")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // DNS, connect, timeout: the API is down or Tailscale is off. Either way, no data.
            throw .unreachable
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = try? decoder.decode(Envelope<Value>.self, from: data)
        switch code {
        case 200..<300:
            guard let result = envelope?.result else { throw .unreadable }
            return result
        case 400..<500:
            throw .rejected(envelope?.error ?? "The Ledger API refused that (HTTP \(code)).")
        case 502, 503, 504:
            // tailscale serve answers, but nothing listens behind it.
            throw .apiDown
        default:
            throw .http(code)
        }
    }

    /// `GET /api/tools`: every tool the API serves (the MCP server's, plus the app's extras), described.
    static func toolCatalog() async throws(LedgerError) -> [ToolInfo] {
        let url = baseURL.deletingLastPathComponent().appending(path: "tools")
        let data: Data
        do {
            (data, _) = try await session.data(from: url)
        } catch {
            throw .unreachable
        }
        guard let tools = try? decoder.decode([ToolInfo].self, from: data) else { throw .unreadable }
        return tools
    }

    /// Whether the MCP server answers at all: it refuses anyone without a sign-in or token (401), which is
    /// what a healthy one does. nil when nothing answered.
    static func mcpStatusCode() async -> Int? {
        guard let url = ServerConfig.mcpURL else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "GET"
        guard let (_, response) = try? await session.data(for: request) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
    }
}
