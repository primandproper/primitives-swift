/// Collects data about customers, ported from platform-go's `analytics.EventReporter` interface
/// (`event_reporter.go`):
/// ```go
/// type EventReporter interface {
///   Close()
///   AddUser(ctx context.Context, userID string, properties map[string]any) error
///   EventOccurred(ctx context.Context, event, userID string, properties map[string]any) error
///   EventOccurredAnonymous(ctx context.Context, event, anonymousID string, properties map[string]any) error
/// }
/// ```
/// `context.Context` is dropped (per this port's settled conventions — see `PORTING.md`); every method
/// is `async throws` instead so a real network-backed conformer can suspend and fail without Go's
/// explicit `ctx`/`error` plumbing. `Close()` is `async` (not just synchronous) for the same reason: a
/// real backend's shutdown may need to flush buffered events before returning.
public protocol EventReporter: Sendable {
  /// Flushes and releases any underlying client resources. Mirrors Go's `Close()`.
  func close() async

  /// Upserts a user's identity and traits. Mirrors Go's `AddUser`.
  func addUser(userID: String, properties: [String: AnalyticsPropertyValue]) async throws

  /// Records `event` against an identified user. Mirrors Go's `EventOccurred`.
  func eventOccurred(
    event: String, userID: String, properties: [String: AnalyticsPropertyValue]
  ) async throws

  /// Records `event` against an anonymous visitor. Mirrors Go's `EventOccurredAnonymous`.
  func eventOccurredAnonymous(
    event: String, anonymousID: String, properties: [String: AnalyticsPropertyValue]
  ) async throws
}

extension EventReporter {
  /// Convenience overload for a call site with no properties to attach. Swift protocol requirements
  /// can't carry default argument values, so this fills the role Go's `map[string]any{}`/`nil` argument
  /// played at call sites that didn't need properties.
  public func addUser(userID: String) async throws {
    try await addUser(userID: userID, properties: [:])
  }

  public func eventOccurred(event: String, userID: String) async throws {
    try await eventOccurred(event: event, userID: userID, properties: [:])
  }

  public func eventOccurredAnonymous(event: String, anonymousID: String) async throws {
    try await eventOccurredAnonymous(event: event, anonymousID: anonymousID, properties: [:])
  }
}
