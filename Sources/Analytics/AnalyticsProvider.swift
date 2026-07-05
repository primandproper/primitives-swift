import Foundation

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

/// Errors thrown by ``SourceConfig/provideCollector()``.
///
/// Neither Segment nor PostHog ships a first-party Swift/iOS SDK — both are server-side Go SDKs
/// (`segmentio/analytics-go`, `posthog/posthog-go`) in the origin. Vendoring a server SDK (or a heavy
/// third-party client) is out of scope for this port, so both recognized providers get the same
/// treatment ``Cryptography``'s `salsa20` `EncryptionProvider` case does: the config still decodes, but
/// the factory refuses to hand back a reporter it can't honor.
public enum AnalyticsError: Error, Equatable, Sendable {
  /// `provider` is recognized but has no backend available on this platform.
  case unsupportedProvider(AnalyticsProvider)
}

extension AnalyticsError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unsupportedProvider(let provider):
      return
        "unsupported analytics provider: \(provider.rawValue) (no native iOS SDK; vendor server SDK)"
    }
  }
}
