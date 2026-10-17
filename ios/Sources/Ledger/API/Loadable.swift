/// A value that is loading, loaded, or failed with a reason. Old values are never kept on failure:
/// money on screen must be current or visibly missing.
enum Loadable<Value: Sendable>: Sendable {
    case loading
    case loaded(Value)
    case failed(LedgerError)

    var value: Value? {
        if case .loaded(let value) = self { value } else { nil }
    }

    var error: LedgerError? {
        if case .failed(let error) = self { error } else { nil }
    }

    /// Runs one API call off the main actor and wraps its outcome.
    /// Callers check `Task.isCancelled` before storing it, so a superseded load never overwrites a newer one.
    /// The closure is untyped only because closures don't infer typed throws; every call it makes throws `LedgerError`.
    static func capture(_ call: @Sendable () async throws -> Value) async -> Loadable<Value> {
        do {
            return .loaded(try await call())
        } catch {
            return .failed(LedgerError(error))
        }
    }
}
