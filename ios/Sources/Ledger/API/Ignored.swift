/// The answer of a write tool the app doesn't read back: any JSON decodes, nothing is kept.
struct Ignored: Decodable, Sendable {
    init(from decoder: any Decoder) throws {}
}
