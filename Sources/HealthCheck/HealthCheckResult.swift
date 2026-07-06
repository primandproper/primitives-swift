/// Component health status, ported verbatim from platform-go's `healthcheck.Status`
/// (`StatusUp`/`StatusDown`).
public enum Status: String, Codable, Sendable, Equatable {
  case up
  case down
}

/// The result of a single component check, ported from platform-go's `healthcheck.ComponentResult`:
/// ```go
/// type ComponentResult struct {
///   Status  Status `json:"status"`
///   Message string `json:"message,omitempty"`
/// }
/// ```
/// `message`'s `omitempty` survives the port for free: `JSONEncoder` already omits a `nil` `Optional`
/// field rather than encoding `null`.
public struct ComponentResult: Codable, Sendable, Equatable {
  public var status: Status
  public var message: String?

  public init(status: Status, message: String? = nil) {
    self.status = status
    self.message = message
  }
}

/// The aggregate result of all health checks, ported from platform-go's `healthcheck.Result`.
///
/// Named ``HealthCheckResult`` rather than a bare `Result` — Go's type name is free to reuse since Go has
/// no generic `Result`, but Swift's standard library already owns that identifier for
/// `Result<Success, Failure>`; shadowing it would force every call site to disambiguate.
public struct HealthCheckResult: Codable, Sendable, Equatable {
  public var components: [String: ComponentResult]
  public var status: Status

  public init(status: Status, components: [String: ComponentResult] = [:]) {
    self.status = status
    self.components = components
  }
}
