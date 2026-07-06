/// A ``Checker`` that always reports healthy. Go's `healthcheck` package has no dedicated no-op checker
/// (its zero-checker registry already reports ``Status/up``), but this port's settled convention ships one
/// per protocol regardless — a harmless placeholder for wiring/tests that need *a* checker without caring
/// about its outcome.
public struct NoopChecker: Checker {
  public let name: String

  public init(name: String = "noop") {
    self.name = name
  }

  public func check() async throws {}
}
