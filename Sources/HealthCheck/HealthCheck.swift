/// # HealthCheck
///
/// Ported from platform-go's `healthcheck` package (`healthcheck.go` + `checkers.go`) — the
/// registry-and-aggregation core plus a from-scratch iOS checker set, per `PORTING.md`'s Wave 5 plan.
///
/// What travels over intact:
///   * ``Checker`` — the per-component seam protocol (``Checker/name``, ``Checker/check()``).
///   * ``HealthCheckRegistry`` — the registration + concurrent aggregation engine (``HealthCheckRegistry/register(_:)``,
///     ``HealthCheckRegistry/checkAll()``). Go ran each check on its own goroutine under a `sync.WaitGroup`
///     with a per-check `context.WithTimeout`; this port is an `actor` guarding the checker list, fanning
///     each check out over a `TaskGroup` and racing it against `Task.sleep` for a hard per-check timeout.
///   * ``Status`` / ``ComponentResult`` / ``HealthCheckResult`` — the wire-compatible result tree (Go's bare
///     `Result` is renamed ``HealthCheckResult`` to avoid shadowing `Swift.Result`).
///
/// What's new (Go's `healthcheck` package has no counterpart):
///   * ``ReachabilityChecker`` — backed by the `Network` framework's `NWPathMonitor`. Server-side Go has no
///     concept of "is *this* process online," only whether a specific downstream dependency answers.
///   * ``DiskSpaceChecker`` — backed by `URL`'s volume-capacity resource values. An on-device app is
///     positioned to notice local disk pressure in a way a server process typically isn't.
///   * ``HealthCheckConfig`` / ``DiskSpaceCheckerConfig`` — lenient `Codable` configuration so an app can
///     decode the check timeout and disk-space threshold instead of hardcoding them.
///
/// What's collapsed: Go's client-specific factories — `NewDatabaseChecker`, `NewCacheChecker`,
/// `NewMessageQueueChecker` (`checkers.go`) — each wrapped a typed ready/ping client interface. This
/// platform has no server-backed database/cache/message-queue client to wrap (see `PORTING.md`'s dropped
/// backends), so all three collapse into one generic ``ClosureChecker`` that runs an arbitrary async
/// closure. **This module deliberately does not import `Cache`** (built in parallel, elsewhere in this
/// wave): a cache-ping health check is wired by an app-level composition root as
/// `ClosureChecker(name: "cache") { try await cache.ping() }`, not baked into this module.
///
/// Dropped: nothing else. The registry's aggregation semantics (empty registry → `up`; any `down` component
/// → overall `down`) are preserved exactly.
public enum HealthCheck {}
