/// The error a ``Panicker`` conformer throws in place of actually invoking a crash primitive, ported
/// from nothing in Go — Go's `panic` is unconditional and unrecoverable by design, so
/// `platform-go/panicking` has no error type at all. This exists purely as the vehicle that lets
/// ``NoopPanicker`` and ``PanickerMock`` satisfy ``Panicker``'s `throws(PanickingError)` requirements
/// without terminating the process, so a test can assert "a crash was requested" via ordinary
/// `throws`/`#expect(throws:)` machinery instead of catching a real trap (which Swift cannot recover
/// from, unlike Go's `recover()`).
public enum PanickingError: Error, Equatable, Sendable {
  /// An unconditional crash was requested via ``Panicker/crash(_:)`` or ``Panicker/crashf(_:_:)``.
  case crashRequested(message: String)

  /// A debug-only invariant failed via ``Panicker/assert(_:_:)``.
  case assertionFailed(message: String)

  /// An always-checked invariant failed via ``Panicker/precondition(_:_:)``.
  case preconditionFailed(message: String)
}
