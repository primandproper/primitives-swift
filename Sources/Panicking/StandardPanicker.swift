import Foundation

/// The production ``Panicker``, backed by Swift's real crash primitives. Equivalent to Go's unexported
/// `standardPanicker`, constructed via `NewProductionPanicker`.
///
/// None of these methods ever throw ``PanickingError`` — that half of the seam exists only for
/// ``NoopPanicker``/``PanickerMock`` — this conformer either crashes the process or returns normally,
/// exactly like Go's real `panic`.
public struct StandardPanicker: Panicker {
  public init() {}

  /// Crashes unconditionally via `fatalError`. Mirrors Go's `standardPanicker.Panic`.
  public func crash(_ message: String) -> Never {
    fatalError(message)
  }

  /// Crashes unconditionally via `fatalError`, formatting `format`/`arguments` first. Mirrors Go's
  /// `standardPanicker.Panicf`, which builds its message with `fmt.Sprintf` before panicking.
  public func crashf(_ format: String, _ arguments: CVarArg...) -> Never {
    fatalError(String(format: format, arguments: arguments))
  }

  /// Traps via `assertionFailure` if `condition` is `false` — a no-op in an optimized (non-`-Onone`)
  /// build, matching Swift's own `assert(_:_:)`.
  public func assert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    Swift.assert(condition(), message())
  }

  /// Traps via `preconditionFailure` if `condition` is `false` — checked in both debug and release
  /// builds (only `-Ounchecked` compiles it out), matching Swift's own `precondition(_:_:)`.
  public func precondition(
    _ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String
  ) {
    Swift.precondition(condition(), message())
  }
}
