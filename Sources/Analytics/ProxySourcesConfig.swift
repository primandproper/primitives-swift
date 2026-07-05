import Foundation

/// Per-source analytics config for the analytics proxy, ported from platform-go's
/// `analyticscfg.ProxySourcesConfig`. Sources are codified: `ios` and `web`.
public struct ProxySourcesConfig: Codable, Sendable, Equatable {
  public var ios: SourceConfig?
  public var web: SourceConfig?

  public init(ios: SourceConfig? = nil, web: SourceConfig? = nil) {
    self.ios = ios
    self.web = web
  }

  private enum CodingKeys: String, CodingKey {
    case ios
    case web
  }

  /// Fills unset fields on every configured source with Go's defaults.
  public mutating func ensureDefaults() {
    ios?.ensureDefaults()
    web?.ensureDefaults()
  }

  /// Returns a map of source name to config, for use by ``MultiSourceEventReporter``. Skips nil
  /// entries. Mirrors Go's `ProxySourcesConfig.ToMap`.
  public func toMap() -> [String: SourceConfig] {
    var sources: [String: SourceConfig] = [:]
    if let ios {
      sources["ios"] = ios
    }
    if let web {
      sources["web"] = web
    }
    return sources
  }
}
