import Foundation

/// Configuration for the StoreKit provider. There is no Go origin for this — Go's `capitalism` only
/// knew Stripe, whose config was an API key + webhook secret. StoreKit needs neither: the product
/// catalog, pricing, and entitlements all live in App Store Connect, and signing is handled by the OS.
///
/// The one genuinely useful knob is the set of product identifiers the app sells, so a caller can
/// preload the catalog. It's optional — ``StoreKitPurchaseManager/products(for:)`` accepts arbitrary
/// identifiers regardless.
public struct StoreKitConfig: Codable, Sendable, Equatable {
  /// The App Store product identifiers this app offers.
  public var productIdentifiers: [String]

  public init(productIdentifiers: [String] = []) {
    self.productIdentifiers = productIdentifiers
  }

  private enum CodingKeys: String, CodingKey {
    case productIdentifiers
  }

  /// A missing key decodes to the empty list rather than failing, matching how a partial JSON object
  /// unmarshals into a Go struct's zero value.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    productIdentifiers = try container.decodeIfPresent([String].self, forKey: .productIdentifiers) ?? []
  }
}
