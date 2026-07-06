import Foundation
import Observability

/// The live ``PurchaseManager``, orchestrating Apple's built-in **StoreKit 2** through the
/// ``StoreKitClient`` seam. This is the iOS-native replacement for platform-go's `capitalism/stripe`
/// package: where the Go manager wrapped the Stripe server SDK, this wraps the on-device App Store APIs.
/// No external dependency — StoreKit ships with the OS, the same "use the native framework" choice this
/// port makes for CryptoKit (``Cryptography``) and CoreImage (``QRCodes``).
///
/// This type carries just the cross-cutting concerns — an ``Observability/Observer`` span around every
/// call and the SVC-02 typed-error classification — and delegates every StoreKit touchpoint to its
/// injected ``StoreKitClient`` (``SystemStoreKitClient`` by default). Splitting the raw StoreKit work
/// out behind that seam is what makes the manager's orchestration unit-testable with a fake client; see
/// `StoreKitPurchaseManagerTests`.
///
/// An `actor` because it holds injected reference state and mirrors StoreKit's own actor-isolated
/// surface; the observability uses the manual `begin`/`end` form (not the closure form) so no
/// actor-isolated closure crosses into the nonisolated generic `operation`.
public actor StoreKitPurchaseManager: PurchaseManager {
  /// Observability name for this component, feeding the observer's logger name and span names —
  /// mirrors the `implementationName`/`o11yName` const convention across the platform packages.
  public static let o11yName = "storekit_purchase_manager"

  private let observer: any Observer
  private let client: any StoreKitClient
  /// Product identifiers this app sells, from ``StoreKitConfig/productIdentifiers``. Not required —
  /// ``products(for:)`` accepts any identifiers — but retained so a caller can preload the catalog.
  public let knownProductIdentifiers: [String]

  /// - Parameters:
  ///   - productIdentifiers: the app's known product identifiers (a convenience for preloading).
  ///   - observer: the observability sink wrapping each call.
  ///   - client: the StoreKit seam. Defaults to the live ``SystemStoreKitClient``; tests inject a fake.
  public init(
    productIdentifiers: [String] = [],
    observer: any Observer,
    client: any StoreKitClient = SystemStoreKitClient()
  ) {
    self.knownProductIdentifiers = productIdentifiers
    self.observer = observer
    self.client = client
  }

  public func products(for identifiers: [String]) async throws -> [PurchaseProduct] {
    let op = observer.begin()
    defer { op.end() }
    op.set("storekit.requested_count", identifiers.count)
    do {
      let products = try await client.products(for: identifiers)
      op.set("storekit.fetched_count", products.count)
      return products
    } catch {
      throw op.error(error, "fetching products")
    }
  }

  public func purchase(productID: String, options: PurchaseOptions) async throws -> PurchaseResult {
    let op = observer.begin()
    defer { op.end() }
    op.set("storekit.product_id", productID)
    do {
      let result = try await client.purchase(productID: productID, options: options)
      switch result {
      case .success(let entitlement, _):
        op.set("storekit.transaction_id", entitlement.transactionID)
      case .pending:
        op.set("storekit.result", "pending")
      case .userCancelled:
        op.set("storekit.result", "user_cancelled")
      }
      return result
    } catch {
      // Surface a typed ``CapitalismError`` so callers can `catch` it (SVC-02): a ``CapitalismError``
      // from the client (verification/`@unknown`/not-found) passes through raw; any other StoreKit
      // error is classified as ``CapitalismError/purchaseFailed(_:)``. `acknowledge` records it without
      // the `ObservabilityError` wrapping that `op.error` would add (which is what erased the type).
      let failure = Self.classifyPurchaseError(error)
      op.acknowledge(failure, "purchasing product")
      throw failure
    }
  }

  public func currentEntitlements() async -> [Entitlement] {
    let op = observer.begin()
    defer { op.end() }
    let entitlements = await client.currentEntitlements()
    op.set("storekit.entitlement_count", entitlements.count)
    return entitlements
  }

  public func restorePurchases() async throws {
    let op = observer.begin()
    defer { op.end() }
    do {
      try await client.sync()
    } catch {
      throw op.error(error, "restoring purchases")
    }
  }

  public nonisolated func transactionUpdates() -> AsyncStream<TransactionUpdate> {
    client.transactionUpdates()
  }

  /// Maps an error thrown while completing a purchase onto the typed ``CapitalismError`` the manager
  /// surfaces: a ``CapitalismError`` passes through raw, and any other error is classified as
  /// ``CapitalismError/purchaseFailed(_:)`` (keeping StoreKit's non-`Equatable` error type off the
  /// public boundary). Extracted so the typed-error contract is unit-testable without a live purchase.
  static func classifyPurchaseError(_ error: Error) -> CapitalismError {
    if let capitalism = error as? CapitalismError { return capitalism }
    return .purchaseFailed(String(describing: error))
  }
}
