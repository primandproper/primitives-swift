import Foundation

/// The recognized payment backends, ported from the `StripeProvider` string constant in platform-go's
/// `capitalism/config/config.go` — but re-pointed for iOS.
///
/// Go's origin had exactly one provider (`stripe`). This port drops Stripe (its interface is
/// server-shaped: webhooks, payment intents, customer creation — none of which happen on-device) and
/// swaps in the two that make sense for an iOS client:
///
/// - ``storeKit`` — Apple's built-in StoreKit 2. The live, dependency-free default, implemented by
///   ``StoreKitPurchaseManager``.
/// - ``revenueCat`` — RevenueCat's SDK. Recognized and configurable, but **salsa20-treated** the way
///   ``Analytics``'s Segment/PostHog providers are: the config decodes, but the factory refuses to hand
///   back a manager it can't honor, because vendoring the RevenueCat SDK is out of scope for this
///   dependency-light package. A consuming app wires its own thin ``PurchaseManager`` adapter over
///   `Purchases.shared`.
///
/// Kept as a resolved-from-`String` enum (see ``CapitalismConfig/resolvedProvider``) rather than
/// decoding the provider field straight into this type, so an empty/unrecognized value degrades
/// leniently instead of failing to decode — matching the Go origin's string-keyed switch.
public enum CapitalismProvider: String, Codable, Sendable, CaseIterable, Equatable {
  case storeKit = "storekit"
  case revenueCat = "revenuecat"
}

/// A runtime failure from the payment layer. Split from ``CapitalismConfigError`` (a config-validation
/// failure) the way ``Analytics`` splits `AnalyticsError` from `SourceConfigError`: this covers what can
/// go wrong while *doing* a purchase, plus the salsa20 refusal.
public enum CapitalismError: Error, Equatable, Sendable {
  /// The configured provider is recognized but has no usable backend in this package — the salsa20
  /// treatment. Today only ``CapitalismProvider/revenueCat`` throws this.
  case unsupportedProvider(CapitalismProvider)
  /// A product identifier didn't resolve to any App Store product.
  case productNotFound(String)
  /// StoreKit returned a transaction whose signature failed verification — it must not be trusted or
  /// fulfilled. Mirrors the JWS check StoreKit 2 performs on every transaction.
  case unverifiedTransaction
  /// StoreKit surfaced a purchase result this port doesn't recognize (an `@unknown default`), so the
  /// outcome can't be classified as success/pending/cancelled.
  case unknownPurchaseResult
  /// The underlying StoreKit call failed. Carries the underlying error's description (StoreKit's error
  /// types aren't `Equatable`, so the string keeps this enum comparable for tests).
  case purchaseFailed(String)
}

extension CapitalismError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unsupportedProvider(let provider):
      return
        "unsupported payment provider: \(provider.rawValue) (no in-package backend; wire an adapter)"
    case .productNotFound(let id):
      return "no App Store product found for identifier: \(id)"
    case .unverifiedTransaction:
      return "transaction failed StoreKit signature verification"
    case .unknownPurchaseResult:
      return "StoreKit returned an unrecognized purchase result"
    case .purchaseFailed(let detail):
      return "purchase failed: \(detail)"
    }
  }
}
