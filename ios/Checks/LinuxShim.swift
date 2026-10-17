// Linux-only stand-ins for Apple localization types, so the pure model files compile with swiftc.
// macOS has the real ones in Foundation.
#if os(Linux)
typealias LocalizedStringResource = String
extension String { init(localized value: String) { self = value } }
#endif
