import Foundation

/// A ``Panicker`` that never traps the process — the always-safe fallback for a disabled or
/// unconfigured panicking layer, in the spirit of ``NoopEventReporter``/``NoopRetryPolicy``. There is no
/// platform-go analogue (Go's `panicking` package ships no no-op, only `mock/`); this exists solely to
/// satisfy this port's convention that every seam ships a Noop and a Mock (REPO-05).
///
/// ``assert(_:_:)``/``precondition(_:_:)`` are fully inert: `condition` is never even evaluated, so
/// using this conformer is equivalent to compiling all assertions out of the build. ``crash(_:)``/
/// ``crashf(_:_:)`` cannot follow suit — their `-> Never` return type means they can never simply return
/// — so they're the one place this "no-op" isn't silent: they throw ``PanickingError`` instead of
/// invoking the real primitive, which is the only inert option left to a function that can't return
/// normally.
public struct NoopPanicker: Panicker {
  public init() {}

  /// Throws ``PanickingError/crashRequested(message:)`` instead of crashing.
  public func crash(_ message: String) throws(PanickingError) -> Never {
    throw .crashRequested(message: message)
  }

  /// Throws ``PanickingError/crashRequested(message:)`` instead of crashing, formatting `format`/
  /// `arguments` first.
  public func crashf(_ format: String, _ arguments: CVarArg...) throws(PanickingError) -> Never {
    throw .crashRequested(message: String(format: format, arguments: arguments))
  }

  /// Does nothing — `condition` is never evaluated.
  public func assert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {}

  /// Does nothing — `condition` is never evaluated.
  public func precondition(
    _ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String
  ) {}
}
