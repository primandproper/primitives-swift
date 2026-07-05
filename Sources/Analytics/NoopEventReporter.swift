/// A no-op ``EventReporter``, ported from platform-go's `analytics/noop` package. Used as the safe
/// default when no provider is configured (or an unrecognized one is), rather than leaving analytics
/// calls throughout the app nil-checking a reporter that may not exist.
public struct NoopEventReporter: EventReporter {
  public init() {}

  public func close() {}

  public func addUser(userID: String, properties: [String: AnalyticsPropertyValue]) {}

  public func eventOccurred(event: String, userID: String, properties: [String: AnalyticsPropertyValue]) {}

  public func eventOccurredAnonymous(
    event: String, anonymousID: String, properties: [String: AnalyticsPropertyValue]
  ) {}
}
