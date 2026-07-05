import Foundation

/// Configuration for the RevenueCat provider, structurally mirroring how platform-go's `stripe.Config`
/// carried its provider credentials.
///
/// This config is fully faithful and decodes cleanly — only the manager it would configure gets the
/// salsa20 treatment (``CapitalismConfig/provideManager(observer:)`` throws
/// ``CapitalismError/unsupportedProvider(_:)``), exactly as ``Analytics``'s `SegmentConfig` is faithful
/// while its reporter is stubbed. A consuming app that adds the RevenueCat SDK reads this ``apiKey`` to
/// `Purchases.configure(withAPIKey:)` inside its own ``PurchaseManager`` adapter.
public struct RevenueCatConfig: Codable, Sendable, Equatable {
  /// The RevenueCat public SDK API key.
  public var apiKey: String

  public init(apiKey: String = "") {
    self.apiKey = apiKey
  }

  private enum CodingKeys: String, CodingKey {
    case apiKey
  }

  /// A missing key decodes to Go's zero value (`""`) rather than failing.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
  }

  /// Validates the config: the API key is required (mirrors `stripe.Config`'s required-field
  /// validation).
  public func validate() throws {
    if apiKey.isEmpty {
      throw RevenueCatConfigError.missingAPIKey
    }
  }
}

/// A rejected ``RevenueCatConfig``.
public enum RevenueCatConfigError: Error, Equatable, Sendable {
  case missingAPIKey
}

extension RevenueCatConfigError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "apiKey: cannot be blank"
    }
  }
}
