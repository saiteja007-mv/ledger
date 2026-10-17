/// One write against the ledger, from list_audit.
struct AuditEntry: Decodable, Identifiable, Sendable {
    let id: Int
    /// UTC, "YYYY-MM-DD HH:MM:SS".
    let ts: String
    let tool: String
    let actor: String?
    let affected: Int?
    let detail: String?
}
