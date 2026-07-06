/// The recognized analytics backends, ported from the `ProviderSegment`/`ProviderPostHog` string
/// constants in platform-go's `analytics/config/config.go`.
///
/// Go validates the provider as a bare `string` with `validation.In(ProviderSegment, ProviderPostHog)`.
/// ``SourceConfig/provider`` keeps that raw-string shape (so an empty or unrecognized value can resolve
/// leniently to a noop reporter, matching Go's `ProvideCollector` `default` case); this closed enum is
/// what ``SourceConfig/resolvedProvider`` resolves a recognized string into.
public enum AnalyticsProvider: String, Codable, Sendable, CaseIterable {
  case segment
  case posthog
}
