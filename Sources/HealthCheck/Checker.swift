/// Performs a health check for one component, ported from platform-go's `healthcheck.Checker` interface
/// (`healthcheck.go`):
/// ```go
/// type Checker interface {
///   Name() string
///   Check(ctx context.Context) error
/// }
/// ```
/// `context.Context` is dropped per this port's settled conventions — cancellation and deadlines are
/// expressed through Swift structured concurrency instead. Go's `Check(ctx) error` (nil = healthy) becomes
/// `check() async throws` (returns normally = healthy); ``HealthCheckRegistry`` is the only caller that
/// interprets the outcome, converting "returned" into ``Status/up`` and "threw" into ``Status/down`` with
/// the error's message — the same translation Go's registry did with `if err := c.Check(checkCtx); err !=
/// nil`. Individual conformers stay as simple as Go's: report success by returning, failure by throwing.
public protocol Checker: Sendable {
  /// Identifies this component in ``HealthCheckResult/components``. Ported from Go's `Name()`.
  var name: String { get }

  /// Performs the check. Ported from Go's `Check(ctx)`; return normally for healthy, throw for unhealthy.
  ///
  /// Implementations should respect `Task` cancellation where practical (e.g. via a cancellable
  /// `URLSession` task or `Task.sleep`) so ``HealthCheckRegistry``'s per-check timeout can actually bound
  /// them — the same caveat Go's comment carries ("Checks must honor ctx cancellation"). A conformer that
  /// ignores cancellation still gets classified ``Status/down`` on timeout, but the registry's overall
  /// `checkAll()` call won't return until it actually finishes.
  func check() async throws
}
