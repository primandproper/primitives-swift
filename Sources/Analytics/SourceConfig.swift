import CircuitBreaking
import Foundation

/// The per-source analytics config (provider + credentials), ported from platform-go's
/// `analyticscfg.SourceConfig` (`analytics/config/config.go`). Used standalone for a single-provider
/// app and per-entry for ``ProxySourcesConfig`` (the analytics proxy's iOS/web sources).
///
/// Reuses ``CircuitBreaking``'s ``CircuitBreakerConfig`` rather than redefining the
/// `circuitBreakerErrorPercentage`/`circuitBreakerMinimumOccurrenceThreshold` JSON keys a second time —
/// the Go origin embeds `circuitbreakingcfg.Config` for the same reason. The breaker itself is never
/// actually constructed by ``provideCollector()`` today (both recognized providers throw before needing
/// it), but the field is preserved for wire fidelity and for whenever a real backend is wired up.
public struct SourceConfig: Codable, Sendable, Equatable {
  public var segment: SegmentConfig?
  public var posthog: PostHogConfig?
  /// The raw provider string, e.g. `"segment"`/`"posthog"`. Kept as a raw `String` (not
  /// ``AnalyticsProvider``) rather than a closed enum because Go resolves it *leniently*: an empty or
  /// unrecognized value falls back to a noop reporter rather than failing to decode. See
  /// ``resolvedProvider``.
  public var provider: String
  public var circuitBreaker: CircuitBreakerConfig

  public init(
    segment: SegmentConfig? = nil,
    posthog: PostHogConfig? = nil,
    provider: String = "",
    circuitBreaker: CircuitBreakerConfig = CircuitBreakerConfig()
  ) {
    self.segment = segment
    self.posthog = posthog
    self.provider = provider
    self.circuitBreaker = circuitBreaker
  }

  private enum CodingKeys: String, CodingKey {
    case segment
    case posthog
    case provider
    case circuitBreaker
  }

  /// A missing key decodes to Go's zero value rather than failing, matching how a partial JSON object
  /// unmarshals into a Go struct.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    segment = try container.decodeIfPresent(SegmentConfig.self, forKey: .segment)
    posthog = try container.decodeIfPresent(PostHogConfig.self, forKey: .posthog)
    provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
    circuitBreaker =
      try container.decodeIfPresent(CircuitBreakerConfig.self, forKey: .circuitBreaker)
      ?? CircuitBreakerConfig()
  }

  /// The ``AnalyticsProvider`` `provider` resolves to (trimmed, lowercased), or `nil` if empty/
  /// unrecognized — the same lenient-negotiation shape ``Encoding``'s `ContentType.from(header:)` uses.
  public var resolvedProvider: AnalyticsProvider? {
    AnalyticsProvider(rawValue: provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }

  /// Fills unset fields with Go's defaults. Mirrors `SourceConfig.EnsureDefaults`.
  public mutating func ensureDefaults() {
    circuitBreaker.ensureDefaults()
  }

  /// A copy with ``ensureDefaults()`` applied.
  public func ensuringDefaults() -> SourceConfig {
    var copy = self
    copy.ensureDefaults()
    return copy
  }

  /// Validates the config, mirroring Go's `SourceConfig.ValidateWithContext`: the provider is
  /// **required** (unlike the top-level ``AnalyticsConfig``, where it may be left unset), must be a
  /// known provider, and the matching credentials block must be present and itself valid. A proxy
  /// source with no provider/key can't pass validation and silently degrade to a noop at runtime.
  public func validate() throws {
    guard !provider.isEmpty else {
      throw SourceConfigError.providerRequired
    }
    guard let resolved = resolvedProvider else {
      throw SourceConfigError.unknownProvider(provider)
    }

    switch resolved {
    case .segment:
      guard let segment else {
        throw SourceConfigError.missingProviderConfig(.segment)
      }
      do {
        try segment.validate()
      } catch let error as SegmentConfigError {
        throw SourceConfigError.invalidSegmentConfig(error)
      }
    case .posthog:
      guard let posthog else {
        throw SourceConfigError.missingProviderConfig(.posthog)
      }
      do {
        try posthog.validate()
      } catch let error as PostHogConfigError {
        throw SourceConfigError.invalidPostHogConfig(error)
      }
    }
  }

  /// Builds the configured ``EventReporter``, ported from Go's `SourceConfig.ProvideCollector`.
  ///
  /// An empty or unrecognized provider returns ``NoopEventReporter`` (Go's `default` case, which logs
  /// and falls back rather than failing). A recognized provider with no matching credentials block
  /// throws ``SourceConfigError/missingProviderConfig(_:)`` (Go: "segment provider configured but
  /// segment config is nil"). A recognized, fully-configured provider throws
  /// ``AnalyticsError/unsupportedProvider(_:)`` — see ``AnalyticsError`` for why.
  public func provideCollector() throws -> any EventReporter {
    guard let resolved = resolvedProvider else {
      return NoopEventReporter()
    }

    switch resolved {
    case .segment:
      guard segment != nil else {
        throw SourceConfigError.missingProviderConfig(.segment)
      }
      throw AnalyticsError.unsupportedProvider(.segment)
    case .posthog:
      guard posthog != nil else {
        throw SourceConfigError.missingProviderConfig(.posthog)
      }
      throw AnalyticsError.unsupportedProvider(.posthog)
    }
  }
}

/// A rejected ``SourceConfig``. Go returned an aggregate `ozzo-validation` error (plus a formatted error
/// from `ProvideCollector`); the port names each concrete failure mode so a caller can branch on them.
public enum SourceConfigError: Error, Equatable, Sendable {
  /// The provider string was empty.
  case providerRequired
  /// The provider string was non-empty but not `"segment"`/`"posthog"`.
  case unknownProvider(String)
  /// The provider was recognized but its matching credentials block (``SourceConfig/segment`` or
  /// ``SourceConfig/posthog``) was `nil`.
  case missingProviderConfig(AnalyticsProvider)
  case invalidSegmentConfig(SegmentConfigError)
  case invalidPostHogConfig(PostHogConfigError)
}

extension SourceConfigError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .providerRequired:
      return "provider: cannot be blank"
    case .unknownProvider(let provider):
      return "provider: must be a valid value, got \(provider)"
    case .missingProviderConfig(let provider):
      return "\(provider.rawValue) provider configured but \(provider.rawValue) config is nil"
    case .invalidSegmentConfig(let error):
      return "segment: \(error.localizedDescription)"
    case .invalidPostHogConfig(let error):
      return "posthog: \(error.localizedDescription)"
    }
  }
}
