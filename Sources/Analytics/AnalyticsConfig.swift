import Foundation

/// The top-level analytics configuration, ported from platform-go's `analyticscfg.Config`.
///
/// Go embeds `SourceConfig` anonymously alongside a `ProxySources` field:
/// ```go
/// type Config struct {
///   ProxySources ProxySourcesConfig `envPrefix:"PROXY_SOURCES_" json:"proxySources"`
///   SourceConfig
/// }
/// ```
/// An anonymous Go struct field with no `json` tag of its own flattens its fields into the parent
/// object, so the wire shape is `{"proxySources": {...}, "segment": ..., "posthog": ..., "provider":
/// ..., "circuitBreaker": ...}` — `source`'s fields sit at the top level, not nested under a `"source"`
/// key. Swift has no equivalent embedding/flattening, so ``init(from:)``/``encode(to:)`` reproduce it by
/// hand: ``source`` decodes/encodes straight from/to the top-level container, and only ``proxySources``
/// goes through its own keyed slot.
public struct AnalyticsConfig: Codable, Sendable, Equatable {
  public var proxySources: ProxySourcesConfig
  public var source: SourceConfig

  public init(
    proxySources: ProxySourcesConfig = ProxySourcesConfig(), source: SourceConfig = SourceConfig()
  ) {
    self.proxySources = proxySources
    self.source = source
  }

  private enum CodingKeys: String, CodingKey {
    case proxySources
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    proxySources =
      try container.decodeIfPresent(ProxySourcesConfig.self, forKey: .proxySources)
      ?? ProxySourcesConfig()
    source = try SourceConfig(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    try source.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(proxySources, forKey: .proxySources)
  }

  /// Fills unset fields with Go's defaults, mirroring `Config.EnsureDefaults`.
  public mutating func ensureDefaults() {
    source.ensureDefaults()
    proxySources.ensureDefaults()
  }

  /// Validates the config, mirroring Go's `Config.ValidateWithContext`.
  ///
  /// Unlike ``SourceConfig/validate()``, the top-level ``source``'s provider is **not** required — an
  /// app that only uses proxy sources (or none at all) may leave it blank, and it will simply resolve
  /// to a noop reporter at runtime. If it *is* set, though, it must be a recognized provider with its
  /// matching credentials. Every configured proxy source is then validated with the stricter
  /// ``SourceConfig/validate()`` (provider required), matching Go's "a proxy source with no
  /// provider/key can't silently degrade to a noop" intent.
  public func validate() throws {
    if !source.provider.isEmpty {
      guard let resolved = source.resolvedProvider else {
        throw SourceConfigError.unknownProvider(source.provider)
      }
      switch resolved {
      case .segment:
        guard let segment = source.segment else {
          throw SourceConfigError.missingProviderConfig(.segment)
        }
        do {
          try segment.validate()
        } catch let error as SegmentConfigError {
          throw SourceConfigError.invalidSegmentConfig(error)
        }
      case .posthog:
        guard let posthog = source.posthog else {
          throw SourceConfigError.missingProviderConfig(.posthog)
        }
        do {
          try posthog.validate()
        } catch let error as PostHogConfigError {
          throw SourceConfigError.invalidPostHogConfig(error)
        }
      }
    }

    for (name, proxySource) in proxySources.toMap() {
      do {
        try proxySource.validate()
      } catch let error as SourceConfigError {
        throw AnalyticsConfigError.invalidProxySource(name: name, underlying: error)
      }
    }
  }
}

/// A rejected ``AnalyticsConfig``, ported from the `errors.Wrapf(err, "validating %q proxy source",
/// name)` wrapping in Go's `Config.ValidateWithContext`.
public enum AnalyticsConfigError: Error, Equatable, Sendable {
  case invalidProxySource(name: String, underlying: SourceConfigError)
}

extension AnalyticsConfigError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidProxySource(let name, let underlying):
      return "validating \"\(name)\" proxy source: \(underlying.localizedDescription)"
    }
  }
}
