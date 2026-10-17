import CryptoKit
import Foundation

/// Merchant logos, asked of ledger-api once per merchant text and then kept: in memory, and as PNGs in the
/// Caches folder so a relaunch needn't ask again. "No logo" is remembered for a week; an unreachable API is
/// not remembered at all, so the next row that wants the logo tries again.
actor LogoStore {
    static let shared = LogoStore()

    private static let missingTTL: TimeInterval = 7 * 24 * 3600

    private var known: [String: Data] = [:]
    private var missing: Set<String> = []
    private var pending: [String: Task<Data?, Never>] = [:]
    private let directory: URL

    init() {
        directory = URL.cachesDirectory.appending(path: "MerchantLogos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The PNG for a merchant as the transaction spells it, or nil when it has no logo (or can't be asked).
    func logo(for merchant: String) async -> Data? {
        let text = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let key = text.lowercased()
        if let data = known[key] { return data }
        if missing.contains(key) { return nil }

        let name = Self.fileName(key)
        if let data = try? Data(contentsOf: directory.appending(path: name + ".png")) {
            known[key] = data
            return data
        }
        let none = directory.appending(path: name + ".none")
        if let modified = try? none.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date.now.timeIntervalSince(modified) < Self.missingTTL {
            missing.insert(key)
            return nil
        }

        if let task = pending[key] { return await task.value }
        let task = Task { await self.fetch(text, key: key, name: name) }
        pending[key] = task
        let data = await task.value
        pending[key] = nil
        return data
    }

    private func fetch(_ merchant: String, key: String, name: String) async -> Data? {
        do {
            let logo = try await LedgerAPI.merchantLogo(merchant)
            if let data = logo.data {
                known[key] = data
                try? data.write(to: directory.appending(path: name + ".png"), options: .atomic)
                return data
            }
            missing.insert(key)
            try? Data().write(to: directory.appending(path: name + ".none"), options: .atomic)
        } catch {
            // Unreachable or refused: no logo for now, and nothing remembered.
        }
        return nil
    }

    private static func fileName(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
