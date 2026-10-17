/// One tool from `GET /api/tools`: the finance MCP server's tools, plus the few the iOS API adds itself.
struct ToolInfo: Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let description: String?
    /// Served only by the iOS API (categories, networth, receipt upload, merchant logos), not by the MCP server.
    let extra: Bool?

    var id: String { name }
    var isMCP: Bool { extra != true }

    /// Writes change the ledger; everything else only reads it.
    var isWrite: Bool {
        ["upsert_", "set_", "record_", "mark_", "void_", "add_", "upload_"].contains { name.hasPrefix($0) }
    }
}
