/// A configurable ``Checker`` test double, the Swift analogue of platform-go's hand-rolled
/// `mockChecker` (`healthcheck_test.go`), which held a plain `checkFn` closure field.
///
/// Go's test double is a simple, non-concurrent struct — nothing calls it from more than one goroutine at
/// once in the original tests. ``HealthCheckRegistry/checkAll()`` runs every checker concurrently, though,
/// so the recorded-calls bookkeeping needs real synchronization here: this is an `actor`, matching
/// ``Analytics/EventReporterMock`` and ``FeatureFlags/FeatureFlagManagerMock``. An unset `checkHandler`
/// defaults to a healthy no-op check (mirroring Go's `mockChecker.Check`, which returns `nil` when
/// `checkFn` is nil) rather than panicking, since `Checker` has only the one method to stub.
public actor CheckerMock: Checker {
  public let name: String
  public var checkHandler: (@Sendable () async throws -> Void)?

  public private(set) var checkCallCount = 0

  public init(name: String, checkHandler: (@Sendable () async throws -> Void)? = nil) {
    self.name = name
    self.checkHandler = checkHandler
  }

  public func check() async throws {
    checkCallCount += 1
    try await checkHandler?()
  }
}
