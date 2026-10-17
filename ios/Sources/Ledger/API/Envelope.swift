/// Every /api/tool answer: `{"ok": true, "result": ...}` or `{"ok": false, "error": "..."}`.
struct Envelope<Value: Decodable>: Decodable {
    let ok: Bool
    let result: Value?
    let error: String?
}
