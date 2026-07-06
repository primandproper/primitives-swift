import Foundation

/// Abstracts Swift's crash primitives so production code can call `panicker.crash(msg)` rather than
/// `fatalError` directly, letting tests substitute a recording or throwing double instead of actually
/// terminating the process. Ported from platform-go's `panicking.Panicker` interface:
/// ```go
/// type Panicker interface {
///   Panic(any)
///   Panicf(format string, args ...any)
/// }
/// ```
/// Go's single, unconditional `panic` maps onto two Swift primitives with different semantics —
/// `fatalError` (always crashes) and the debug-only `assertionFailure` — plus a third, `precondition`/
/// `preconditionFailure` (always checked, even in a release build), that has no Go equivalent at all.
/// This protocol exposes one method per primitive rather than folding them together, so a conformer's
/// implementation — and a mock's recorded calls — stay unambiguous about which one fired.
///
/// Every requirement is `throws(PanickingError)`. Go's `panic`/`Panic`/`Panicf` never return control to
/// the caller (barring a `recover()` further up the call stack, which Swift has no equivalent of), and
/// ``StandardPanicker`` preserves that: it never throws, it only ever crashes or returns normally. The
/// `throws` is there solely so ``NoopPanicker`` and ``PanickerMock`` have a way to signal "a crash was
/// requested" without a real trap, which is the entire reason this seam exists.
public protocol Panicker: Sendable {
  /// Requests an unconditional, unrecoverable crash with `message`. Mirrors Go's `Panic(msg)`; the
  /// production conformer calls `fatalError`.
  ///
  /// The `-> Never` return means a conformer must either genuinely never return (trap) or leave via
  /// `throws` — there is no way to silently ignore this call, matching `panic`'s unconditional nature.
  func crash(_ message: String) throws(PanickingError) -> Never

  /// Requests an unconditional crash built from a `String(format:)`-style format string and arguments.
  /// Mirrors Go's `Panicf(format, args...)`, which builds its message with `fmt.Sprintf`.
  func crashf(_ format: String, _ arguments: CVarArg...) throws(PanickingError) -> Never

  /// Requests a crash only if `condition` is `false` — a Swift-native addition (Go has no debug-only
  /// assertion). The production conformer calls `assertionFailure`, which — like Swift's own
  /// `assert(_:_:)` — only actually traps in a `-Onone` (debug) build; in an optimized build this is a
  /// silent no-op even when `condition` is `false`.
  ///
  /// `condition` and `message` are autoclosures, matching the standard library's `assert(_:_:)`, so
  /// neither is evaluated in a build configuration where assertions are compiled out.
  func assert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String)
    throws(PanickingError)

  /// Requests a crash only if `condition` is `false` — a Swift-native addition (Go has no equivalent).
  /// The production conformer calls `preconditionFailure`, which — like Swift's own
  /// `precondition(_:_:)` — traps in both debug and release builds (only `-Ounchecked` compiles it out).
  func precondition(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String)
    throws(PanickingError)
}

extension Panicker {
  /// Convenience overload for a call site with no message, mirroring how a Go caller can pass an empty
  /// string. Protocol requirements can't carry default argument values, so this fills that gap.
  public func assert(_ condition: @autoclosure () -> Bool) throws(PanickingError) {
    try assert(condition(), "")
  }

  /// Convenience overload for a call site with no message. See ``assert(_:)``.
  public func precondition(_ condition: @autoclosure () -> Bool) throws(PanickingError) {
    try precondition(condition(), "")
  }
}
