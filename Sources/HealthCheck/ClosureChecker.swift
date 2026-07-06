/// A ``Checker`` that runs an arbitrary async closure, ported from platform-go's generic-client checkers
/// (`healthcheck/checkers.go`'s `NewCacheChecker`/`NewMessageQueueChecker`/`NewDatabaseChecker`), collapsed
/// into one seam.
///
/// Go's three factories each wrap a typed client interface (`CacheReadyChecker.Ping`,
/// `MessageQueueReadyChecker.Ping`, `DatabaseReadyChecker.IsReady`) so a caller passing a concrete Redis or
/// Postgres client gets a `Checker` for free. This platform has no server-backed cache/message-queue/
/// database client to wrap — see `PORTING.md`'s dropped-backends list — so instead of porting three
/// client-specific factories this module ships one generic closure checker and drops the rest. Notably,
/// **this module intentionally does not import `Cache`** (it is a sibling module built independently): a
/// cache-ping health check is wired by an app-level composition root as
/// `ClosureChecker(name: "cache") { try await cache.ping() }` (or whatever the `Cache` module's real seam
/// method ends up being), not baked in here. The same seam covers any other ready/ping-shaped dependency —
/// a database, a message queue, a bespoke service client — without this module ever depending on their
/// concrete types.
public struct ClosureChecker: Checker {
  public let name: String
  private let body: @Sendable () async throws -> Void

  /// - Parameters:
  ///   - name: Identifies this component in ``HealthCheckResult/components``.
  ///   - check: Runs on every ``HealthCheckRegistry/checkAll()`` pass; return normally for healthy, throw
  ///     for unhealthy (the thrown error's message surfaces on the resulting ``ComponentResult``).
  public init(name: String, check: @escaping @Sendable () async throws -> Void) {
    self.name = name
    self.body = check
  }

  public func check() async throws {
    try await body()
  }
}
