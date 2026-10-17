/// Why a Ledger API call gave nothing usable.
enum LedgerError: Error, Equatable, Sendable {
    /// No answer at all: Tailscale is off on this iPhone, or the server is down.
    case unreachable
    /// Tailscale answered for the server, but ledger-api isn't running there.
    case apiDown
    /// The API refused the request and said why: a bad value, an unknown id, too few balances.
    case rejected(String)
    case http(Int)
    case unreadable

    /// For closures, which throw untyped: every API call throws `LedgerError`, anything else means no answer.
    init(_ error: any Error) {
        self = error as? LedgerError ?? .unreachable
    }

    var message: String {
        switch self {
        case .unreachable: "Ledger API unreachable (Tailscale off?)"
        case .apiDown: "Ledger API is down on your server"
        case .rejected(let reason): reason
        case .http(let code): "Ledger API error (HTTP \(code))"
        case .unreadable: "Unreadable answer from the Ledger API"
        }
    }

    var systemImage: String {
        switch self {
        case .unreachable, .apiDown: "wifi.exclamationmark"
        default: "exclamationmark.triangle"
        }
    }
}
