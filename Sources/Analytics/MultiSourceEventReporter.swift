import Foundation

/// Delegates events to per-source ``EventReporter``s, ported from platform-go's
/// `multisource.MultiSourceEventReporter` (`analytics/multisource/reporter.go`).
///
/// This composition is real and useful on its own — it doesn't require a live vendor backend, only
/// *some* ``EventReporter`` per source (``NoopEventReporter``, ``EventReporterMock``, or a future real
/// backend all work). `reporters` is populated at construction and never mutated afterwards, so — like
/// the Go original — reads need no synchronization; a plain `struct` suffices.
public struct MultiSourceEventReporter: Sendable {
  /// The event property used to identify the analytics source (e.g. `ios`, `web`). Mirrors Go's
  /// `SourcePropertyKey`. For a backend sharing one set of credentials across sources (Go's PostHog
  /// dedup case), this property is what distinguishes events by source.
  public static let sourcePropertyKey = "source"

  private let reporters: [String: any EventReporter]

  public init(reporters: [String: any EventReporter] = [:]) {
    self.reporters = reporters
  }

  /// The reporter for `source`, or ``NoopEventReporter`` if unknown/unconfigured. Mirrors Go's
  /// unexported `getReporter`.
  private func reporter(for source: String) -> any EventReporter {
    reporters[source] ?? NoopEventReporter()
  }

  /// The configured source names, mirroring Go's unexported `knownSources` (exposed here since it's
  /// useful for diagnostics/tests without a logger threaded through this type).
  public var knownSources: [String] {
    Array(reporters.keys)
  }

  /// Flushes and closes every underlying reporter. A reporter shared across multiple sources (e.g. a
  /// future backend deduplicated by credentials, as Go's PostHog sources sharing an API key are) is
  /// closed exactly once, matched by reference identity. This only meaningfully deduplicates a
  /// class/actor-based reporter reused across multiple keys (the real sharing case, e.g.
  /// ``EventReporterMock``); a value-typed reporter (like ``NoopEventReporter``) is boxed fresh on each
  /// cast, so equal-content copies are simply closed independently — harmless, since a value type has no
  /// shared mutable state to double-flush.
  public func close() async {
    var seenObjects: Set<ObjectIdentifier> = []
    for reporter in reporters.values {
      let identifier = ObjectIdentifier(reporter as AnyObject)
      guard seenObjects.insert(identifier).inserted else { continue }
      await reporter.close()
    }
  }

  private func withSourceProperty(
    _ source: String, _ properties: [String: AnalyticsPropertyValue]
  ) -> [String: AnalyticsPropertyValue] {
    var merged = properties
    merged[Self.sourcePropertyKey] = .string(source)
    return merged
  }

  /// Records an event for an identified user against `source`'s reporter. Mirrors Go's `TrackEvent`.
  public func trackEvent(
    source: String, event: String, userID: String,
    properties: [String: AnalyticsPropertyValue] = [:]
  ) async throws {
    try await reporter(for: source).eventOccurred(
      event: event, userID: userID, properties: withSourceProperty(source, properties))
  }

  /// Identifies a user against `source`'s reporter. Mirrors Go's `AddUser`.
  public func addUser(
    source: String, userID: String, properties: [String: AnalyticsPropertyValue] = [:]
  ) async throws {
    try await reporter(for: source).addUser(
      userID: userID, properties: withSourceProperty(source, properties))
  }

  /// Records an event for an anonymous visitor against `source`'s reporter. Mirrors Go's
  /// `TrackAnonymousEvent`.
  public func trackAnonymousEvent(
    source: String, event: String, anonymousID: String,
    properties: [String: AnalyticsPropertyValue] = [:]
  ) async throws {
    try await reporter(for: source).eventOccurredAnonymous(
      event: event, anonymousID: anonymousID, properties: withSourceProperty(source, properties))
  }
}

extension MultiSourceEventReporter {
  /// Builds a ``MultiSourceEventReporter`` from proxy sources config, ported from Go's
  /// `ProvideMultiSourceEventReporter`. For each source, attempts to build an ``EventReporter`` via
  /// `makeReporter` (defaulting to ``SourceConfig/provideCollector()``); if that throws — e.g. missing
  /// credentials, or (today, always, since neither ships an iOS SDK) a recognized Segment/PostHog
  /// provider — the source falls back to ``NoopEventReporter``, exactly like the Go original.
  ///
  /// For PostHog, reporters are deduplicated by API key: sources sharing the same key reuse a single
  /// reporter instance (the source property still distinguishes their events), while sources with
  /// distinct keys each get their own. `makeReporter` is injectable so this dedup/fallback behavior is
  /// testable independent of whether a real backend exists yet.
  public init(
    proxySources: [String: SourceConfig],
    makeReporter: (SourceConfig) throws -> any EventReporter = { try $0.provideCollector() }
  ) {
    var reporters: [String: any EventReporter] = [:]
    var postHogReportersByKey: [String: any EventReporter] = [:]

    for (source, sourceConfig) in proxySources {
      let provider = sourceConfig.resolvedProvider

      var postHogKey: String?
      if provider == .posthog, let apiKey = sourceConfig.posthog?.apiKey, !apiKey.isEmpty {
        postHogKey = apiKey
        if let existing = postHogReportersByKey[apiKey] {
          reporters[source] = existing
          continue
        }
      }

      do {
        let reporter = try makeReporter(sourceConfig)
        if let postHogKey {
          postHogReportersByKey[postHogKey] = reporter
        }
        reporters[source] = reporter
      } catch {
        reporters[source] = NoopEventReporter()
      }
    }

    self.init(reporters: reporters)
  }
}
