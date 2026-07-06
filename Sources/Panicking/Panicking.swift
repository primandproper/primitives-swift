/// # Panicking
///
/// Ported from platform-go's `panicking` package (`panicker.go` + `mock/`) — an abstraction over Go's
/// `panic` built-in, so code that must crash on an unrecoverable invariant violation can be tested
/// without actually tearing down the process.
///
/// What travels over intact:
///   * ``Panicker`` — the seam protocol. Go's `Panic(any)` / `Panicf(format, args...)` become
///     ``Panicker/crash(_:)`` / ``Panicker/crashf(_:_:)``, and gain two Swift-native additions with no
///     Go analogue — ``Panicker/assert(_:_:)`` / ``Panicker/precondition(_:_:)`` — because Swift, unlike
///     Go, distinguishes a debug-only assertion from an always-checked invariant. All four requirements
///     are `throws(PanickingError)` (rather than Go's unconditional `panic`) purely so a test double can
///     satisfy them by throwing instead of trapping; see ``PanickingError``.
///   * ``StandardPanicker`` — the production conformer, mirroring Go's unexported `standardPanicker`
///     (constructed via `NewProductionPanicker`). It calls the real `fatalError`/`assertionFailure`/
///     `preconditionFailure` and never throws.
///   * ``NoopPanicker`` and ``PanickerMock`` — the inert and recording test doubles (REPO-05: every seam
///     ships a Noop and a Mock). Go's `panicking` package ships no no-op (only `mock/`); the no-op has no
///     Go analogue and exists solely to satisfy this port's convention.
///
/// Dropped: nothing backend-shaped — this package has no I/O, config, or server dependency to drop.
public enum Panicking {}
