import Foundation
import os

/// A recording ``Panicker`` test double: it captures every call for later inspection and, by default,
/// throws ``PanickingError`` instead of invoking the real crash primitive, so a test can assert "a crash
/// was requested" — via either the `*Calls` arrays or a caught ``PanickingError`` — without terminating
/// the test runner.
///
/// Go's `panicking/mock` package generates a moq-style `PanickerMock` with per-method `*Func` fields and
/// `*Calls()` accessors. This port folds that into a hand-written recorder in the REPO-05 mold (matching
/// ``MockCookieManaging``/``MockRetryPolicy``): a lock-backed `final class` rather than an `actor`,
/// because ``Panicker``'s requirements are *synchronous* (typed `throws(PanickingError)`, no `async`) to
/// match ``StandardPanicker`` exactly — an actor's `async` methods couldn't satisfy them — so an
/// `OSAllocatedUnfairLock` guards the recorded calls instead.
///
/// ``crash(_:)``/``crashf(_:_:)`` always append to their call log, since Go's `Panic`/`Panicf` are
/// unconditional. ``assert(_:_:)``/``precondition(_:_:)`` also always append — recording every
/// invocation, not just failures — so a test can assert a passing check was still consulted; whether
/// that call additionally throws/traps depends on `condition` being `false`, exactly like the real
/// primitives.
public final class PanickerMock: Panicker, @unchecked Sendable {
  /// A recorded ``crash(_:)``/``crashf(_:_:)`` invocation.
  public struct CrashCall: Sendable, Equatable {
    public let message: String
  }

  /// A recorded ``assert(_:_:)``/``precondition(_:_:)`` invocation.
  public struct ConditionalCall: Sendable, Equatable {
    public let condition: Bool
    public let message: String
  }

  private struct State {
    var crashCalls: [CrashCall] = []
    var crashfCalls: [CrashCall] = []
    var assertCalls: [ConditionalCall] = []
    var preconditionCalls: [ConditionalCall] = []
    var shouldThrow: Bool
  }

  private let state: OSAllocatedUnfairLock<State>

  public var crashCalls: [CrashCall] { state.withLock { $0.crashCalls } }
  public var crashfCalls: [CrashCall] { state.withLock { $0.crashfCalls } }
  public var assertCalls: [ConditionalCall] { state.withLock { $0.assertCalls } }
  public var preconditionCalls: [ConditionalCall] { state.withLock { $0.preconditionCalls } }

  /// - Parameter shouldThrow: when `true` (the default), a requested crash or failed
  ///   assertion/precondition throws ``PanickingError`` instead of invoking the real primitive — the
  ///   safe behavior for a test runner. Pass `false` to have this mock actually call
  ///   `fatalError`/`assertionFailure`/`preconditionFailure`, e.g. to verify integration with the live
  ///   primitives from a subprocess-isolated test harness that expects the process to terminate.
  public init(shouldThrow: Bool = true) {
    state = OSAllocatedUnfairLock(initialState: State(shouldThrow: shouldThrow))
  }

  /// Reconfigures whether a subsequent crash/failed check throws or actually traps. A plain mutator
  /// method (not a `public var`) so this stays safe to call across isolation domains.
  public func setShouldThrow(_ shouldThrow: Bool) {
    state.withLock { $0.shouldThrow = shouldThrow }
  }

  public func crash(_ message: String) throws(PanickingError) -> Never {
    let shouldThrow = state.withLock { s -> Bool in
      s.crashCalls.append(CrashCall(message: message))
      return s.shouldThrow
    }
    if shouldThrow {
      throw .crashRequested(message: message)
    }
    fatalError(message)
  }

  public func crashf(_ format: String, _ arguments: CVarArg...) throws(PanickingError) -> Never {
    let message = String(format: format, arguments: arguments)
    let shouldThrow = state.withLock { s -> Bool in
      s.crashfCalls.append(CrashCall(message: message))
      return s.shouldThrow
    }
    if shouldThrow {
      throw .crashRequested(message: message)
    }
    fatalError(message)
  }

  public func assert(
    _ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String
  ) throws(PanickingError) {
    let conditionValue = condition()
    let messageValue = message()
    let shouldThrow = state.withLock { s -> Bool in
      s.assertCalls.append(ConditionalCall(condition: conditionValue, message: messageValue))
      return s.shouldThrow
    }
    guard !conditionValue else { return }
    if shouldThrow {
      throw .assertionFailed(message: messageValue)
    }
    Swift.assertionFailure(messageValue)
  }

  public func precondition(
    _ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String
  ) throws(PanickingError) {
    let conditionValue = condition()
    let messageValue = message()
    let shouldThrow = state.withLock { s -> Bool in
      s.preconditionCalls.append(ConditionalCall(condition: conditionValue, message: messageValue))
      return s.shouldThrow
    }
    guard !conditionValue else { return }
    if shouldThrow {
      throw .preconditionFailed(message: messageValue)
    }
    Swift.preconditionFailure(messageValue)
  }
}
