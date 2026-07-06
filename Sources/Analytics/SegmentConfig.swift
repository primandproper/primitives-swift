import Foundation

/// Configuration for the Segment analytics backend, ported from platform-go's `segment.Config`
/// (`analytics/segment/config.go`).
///
/// Go's struct carries an `env:"API_TOKEN" json:"apiToken"` string; per this port's settled
/// conventions, only the JSON contract survives, with the coding key preserved so a Go-authored config
/// still decodes.
///
/// This config drives a real ``SegmentEventReporter``: a thin URLSession + Codable upload to Segment's
/// `POST /v1/batch` HTTP API. Segment *does* ship a first-party Swift SDK (`analytics-swift`) — the port
/// reimplements the batch call directly only because of this port's no-vendor-SDK policy, not for lack
/// of one.
public struct SegmentConfig: Codable, Sendable, Equatable {
  public var apiToken: String

  public init(apiToken: String = "") {
    self.apiToken = apiToken
  }

  private enum CodingKeys: String, CodingKey {
    case apiToken
  }

  /// A missing key decodes to Go's zero value (`""`) rather than failing, matching how a partial JSON
  /// object unmarshals into a Go struct.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    apiToken = try container.decodeIfPresent(String.self, forKey: .apiToken) ?? ""
  }

  /// Validates the config, mirroring Go's `ValidateWithContext` (`APIToken` required).
  public func validate() throws {
    if apiToken.isEmpty {
      throw SegmentConfigError.missingAPIToken
    }
  }
}

/// A rejected ``SegmentConfig``. Go returned an `ozzo-validation` error; the port names the one concrete
/// failure mode.
public enum SegmentConfigError: Error, Equatable, Sendable {
  case missingAPIToken
}

extension SegmentConfigError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .missingAPIToken:
      return "apiToken: cannot be blank"
    }
  }
}
