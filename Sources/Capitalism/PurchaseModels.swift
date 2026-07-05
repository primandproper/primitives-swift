import Foundation

/// The kind of product being sold, ported from StoreKit's `Product.ProductType` into a closed,
/// StoreKit-free enum this module owns.
///
/// Keeping it independent of StoreKit is deliberate: ``PurchaseProduct`` and the rest of the value
/// layer must be constructible by ``NoopPurchaseManager``/``PurchaseManagerMock`` and by tests
/// *without* a live App Store fetch, so only ``StoreKitPurchaseManager`` ever imports StoreKit.
public enum ProductType: String, Codable, Sendable, CaseIterable, Equatable {
  /// A one-off purchase that can be bought repeatedly (e.g. a pack of coins).
  case consumable
  /// A one-off purchase owned permanently (e.g. unlocking a feature).
  case nonConsumable
  /// An auto-renewing subscription. The client analogue of Go's `CreateSubscription`.
  case autoRenewable
  /// A fixed-length, non-renewing subscription.
  case nonRenewable
}

/// A product available for purchase, ported from StoreKit's opaque `Product` into a value type this
/// module owns. Only the display-relevant fields cross the boundary; the underlying `Product` handle
/// stays inside ``StoreKitPurchaseManager`` (which re-resolves it by ``id`` at purchase time), so this
/// stays a plain `Sendable`/`Codable` value.
public struct PurchaseProduct: Codable, Sendable, Equatable, Identifiable {
  /// The App Store product identifier.
  public let id: String
  /// Localized product name for display.
  public let displayName: String
  /// Localized product description.
  public let description: String
  /// The price in the storefront currency, as a `Decimal` (StoreKit's `price`).
  public let price: Decimal
  /// The localized, currency-formatted price string (StoreKit's `displayPrice`).
  public let displayPrice: String
  /// The kind of product.
  public let type: ProductType

  public init(
    id: String,
    displayName: String,
    description: String,
    price: Decimal,
    displayPrice: String,
    type: ProductType
  ) {
    self.id = id
    self.displayName = displayName
    self.description = description
    self.price = price
    self.displayPrice = displayPrice
    self.type = type
  }
}

/// A right the user currently holds, derived from a verified StoreKit transaction. Replaces the
/// server-side notion of a subscription/customer record: on-device, "what does this user own?" is
/// answered by reading the App Store's current entitlements, not by querying a payments backend.
public struct Entitlement: Codable, Sendable, Equatable, Identifiable {
  /// The App Store product identifier this entitlement grants.
  public let productID: String
  /// The originating transaction's identifier (StoreKit's `Transaction.id`), as a string so the wire
  /// shape doesn't depend on StoreKit's `UInt64` representation.
  public let transactionID: String
  /// When the purchase was made.
  public let purchaseDate: Date
  /// When the entitlement expires; `nil` for non-consumables and consumables (which never expire).
  public let expirationDate: Date?
  /// Whether the entitlement is active right now (not revoked, and not past its expiration).
  public let isActive: Bool

  /// ``Identifiable`` conformance keys off the transaction id.
  public var id: String { transactionID }

  public init(
    productID: String,
    transactionID: String,
    purchaseDate: Date,
    expirationDate: Date?,
    isActive: Bool
  ) {
    self.productID = productID
    self.transactionID = transactionID
    self.purchaseDate = purchaseDate
    self.expirationDate = expirationDate
    self.isActive = isActive
  }
}

/// Optional knobs for a purchase.
public struct PurchaseOptions: Sendable, Equatable {
  /// A UUID tying this purchase to a backend user account — StoreKit's `Product.PurchaseOption
  /// .appAccountToken`. This is the on-device analogue of Go's `CustomerID`/`CreateCustomer`: rather
  /// than the server minting a customer record up front, the client stamps the App Store transaction
  /// with the account token, which then surfaces on the server-side App Store notification.
  public var appAccountToken: UUID?
  /// Quantity for a consumable purchase (StoreKit's `.quantity` option). `nil` means the StoreKit
  /// default of 1.
  public var quantity: Int?

  public init(appAccountToken: UUID? = nil, quantity: Int? = nil) {
    self.appAccountToken = appAccountToken
    self.quantity = quantity
  }
}

/// The outcome of a purchase attempt, ported from StoreKit's `Product.PurchaseResult`.
public enum PurchaseResult: Sendable, Equatable {
  /// The purchase completed and its transaction verified; carries the granted ``Entitlement``.
  case success(Entitlement)
  /// The purchase is deferred pending external action (e.g. Ask to Buy, or Strong Customer
  /// Authentication). No entitlement yet; watch ``PurchaseManager/transactionUpdates()`` for the
  /// eventual resolution.
  case pending
  /// The user dismissed the purchase sheet.
  case userCancelled
}

/// A transaction that arrived out-of-band — a renewal, a revocation, an Ask-to-Buy approval, or a
/// purchase made on another device. Delivered by ``PurchaseManager/transactionUpdates()``. This is the
/// on-device replacement for Go's `HandleEventWebhook`: instead of the server verifying an inbound
/// provider webhook, the client observes StoreKit's own verified transaction feed.
public struct TransactionUpdate: Sendable, Equatable {
  /// The entitlement state after this update (check ``Entitlement/isActive`` to distinguish a renewal
  /// from a revocation/expiration).
  public let entitlement: Entitlement

  public init(entitlement: Entitlement) {
    self.entitlement = entitlement
  }
}
