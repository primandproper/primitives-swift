import Foundation

/// Tracks failures and successes to decide whether an operation should proceed — ported from
/// platform-go's `circuitbreaking.CircuitBreaker` interface.
///
/// Go's interface is four synchronous methods (`Failed`, `Succeeded`, `CanProceed`, `CannotProceed`)
/// backed by a mutex-guarded rolling window. The observable state — trip counts, the open/closed flag,
/// the time the breaker opened — is *mutable shared state*, so the Swift port models the stateful
/// conformer (``StandardCircuitBreaker``) as an `actor`. That makes the four accessors `async`, which
/// is why this protocol's requirements are `async`: a synchronous conformer (``NoopCircuitBreaker``)
/// still satisfies them, because a non-`async` method fulfills an `async` requirement.
///
/// On top of the Go surface this adds ``execute(_:)`` — the Go package leaves "check, run, report"
/// wiring to each caller, but every caller writes the same three lines, so the port folds them into a
/// default-implemented method a client (e.g. an HTTP client) can lean on directly.
///
/// A tripped breaker is the client-side analogue of the server's `E112 circuitBroken`
/// (`APIErrors.ErrorCode.circuitBroken`): when this breaker is open it short-circuits *locally* with
/// ``CircuitOpenError`` before a doomed request ever leaves the device.
public protocol CircuitBreaker: Sendable {
  /// Records that a guarded operation failed. May trip the breaker open — mirrors Go's `Failed()`.
  func recordFailure() async

  /// Records that a guarded operation succeeded. In the half-open state this closes the breaker —
  /// mirrors Go's `Succeeded()`.
  func recordSuccess() async

  /// Reports whether an operation may proceed (breaker closed, or half-open for a trial) — Go's
  /// `CanProceed()`.
  func canProceed() async -> Bool

  /// The negation of ``canProceed()``, kept as its own method to read cleanly at call sites — Go's
  /// `CannotProceed()`.
  func cannotProceed() async -> Bool

  /// Guards `operation` with the breaker: rejects fast when open, otherwise runs it and reports the
  /// outcome back to the breaker. Default-implemented; see the extension.
  func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T
}

extension CircuitBreaker {
  public func cannotProceed() async -> Bool {
    await !canProceed()
  }

  /// Runs `operation` under the breaker, ported as the Swift-native convenience the Go package never
  /// had (Go callers hand-rolled `if cb.CannotProceed() { … }; cb.Failed()/cb.Succeeded()`).
  ///
  /// - If the breaker is open, throws ``CircuitOpenError`` without invoking `operation` — the whole
  ///   point of a breaker is to stop hammering a failing dependency.
  /// - On success, records a success and returns the value.
  /// - On a thrown error, records a failure and rethrows.
  ///
  /// **Cancellation is not a service failure.** A `CancellationError` (the task was cancelled, not the
  /// dependency misbehaving) is rethrown *without* being counted against the breaker — counting it
  /// would let a burst of user-cancelled requests trip a perfectly healthy circuit. A cancelled
  /// `URLSession` request surfaces as `URLError.cancelled` rather than `CancellationError`, so it is
  /// treated the same way here — consistent with how `HTTPClient` classifies cancellation. This matches
  /// the `Retry` module, which likewise treats cancellation as terminal-but-not-the-dependency's-fault.
  public func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    guard await canProceed() else {
      throw CircuitOpenError()
    }

    do {
      let result = try await operation()
      await recordSuccess()
      return result
    } catch {
      // A cancelled request (task cancellation or a cancelled URLSession task) is not the dependency's
      // fault: rethrow it without recording a breaker failure.
      if error is CancellationError || (error as? URLError)?.code == .cancelled {
        throw error
      }
      await recordFailure()
      throw error
    }
  }
}

/// Thrown by ``CircuitBreaker/execute(_:)`` when the breaker is open and rejects the call without
/// running it.
///
/// There is no Go equivalent thrown from the interface (Go exposes the sentinel
/// `circuitbreaking.ErrCircuitBroken`, "service circuit broken", which callers return themselves after
/// checking `CannotProceed()`). The Swift `execute` does the check, so it needs a typed error to throw;
/// this is it. It carries the breaker's ``name`` for diagnostics and maps conceptually to the wire-level
/// `E112 circuitBroken`.
public struct CircuitOpenError: Error, Equatable {
  /// The configured name of the breaker that rejected the call, when known.
  public let name: String?

  public init(name: String? = nil) {
    self.name = name
  }
}
