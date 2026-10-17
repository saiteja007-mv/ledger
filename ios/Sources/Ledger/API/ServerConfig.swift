import Foundation

/// Where this phone finds its Ledger server: the address typed on the Connect screen (kept on this phone), else
/// the one `scripts/ios-config.cjs` wrote into Info.plist at setup. nil until one of them is set.
/// The widgets only see the Info.plist value, so set it there when you build.
enum ServerConfig {
    static let storedKey = "serverURL"

    static var serverURL: URL? {
        let typed = UserDefaults.standard.string(forKey: storedKey)
        let built = Bundle.main.object(forInfoDictionaryKey: "LedgerServerURL") as? String
        return normalized(typed) ?? normalized(built)
    }

    /// The MCP endpoint for assistants (Claude, ChatGPT), if this server publishes one (`LedgerMCPURL`).
    static var mcpURL: URL? {
        normalized(Bundle.main.object(forInfoDictionaryKey: "LedgerMCPURL") as? String)
    }

    /// "myserver.tailnet.ts.net:8448" or a full http(s) URL. nil for anything that isn't an address.
    static func normalized(_ text: String?) -> URL? {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), ["https", "http"].contains(url.scheme ?? ""),
              let host = url.host(), !host.isEmpty else { return nil }
        return url
    }
}
