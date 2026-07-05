import Foundation

/// Configuration for the PostHog analytics backend, ported from platform-go's `posthog.Config`
/// (`analytics/posthog/config.go`).
///
/// Go's struct carries `env:"API_KEY" json:"apiKey"` and `env:"ENDPOINT" json:"endpoint"`; per this
/// port's settled conventions, only the JSON contract survives, with both coding keys preserved so a
/// Go-authored config still decodes.
///
/// This config is fully faithful — only the reporter it configures
/// (``SourceConfig/provideCollector()``) gets the salsa20 treatment, since PostHog has no iOS SDK.
public struct PostHogConfig: Codable, Sendable, Equatable {
  public var apiKey: String

  /// The PostHog ingestion host. Empty means PostHog US Cloud (the default); set it for EU Cloud
  /// (`https://eu.posthog.com`) or a self-hosted instance. Mirrors Go's `Endpoint` doc comment.
  public var endpoint: String

  public init(apiKey: String = "", endpoint: String = "") {
    self.apiKey = apiKey
    self.endpoint = endpoint
  }

  private enum CodingKeys: String, CodingKey {
    case apiKey
    case endpoint
  }

  /// A missing key decodes to Go's zero value (`""`) rather than failing, matching how a partial JSON
  /// object unmarshals into a Go struct.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
  }

  /// Validates the config, mirroring Go's `ValidateWithContext` (`APIKey` required).
  public func validate() throws {
    if apiKey.isEmpty {
      throw PostHogConfigError.missingAPIKey
    }
  }
}

/// A rejected ``PostHogConfig``. Go returned an `ozzo-validation` error; the port names the one concrete
/// failure mode.
public enum PostHogConfigError: Error, Equatable, Sendable {
  case missingAPIKey
}

extension PostHogConfigError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "apiKey: cannot be blank"
    }
  }
}
