import Foundation
import Observability
import StoreKit

/// The live ``PurchaseManager``, backed by Apple's built-in **StoreKit 2**. This is the iOS-native
/// replacement for platform-go's `capitalism/stripe` package: where the Go manager wrapped the Stripe
/// server SDK, this wraps the on-device App Store APIs (`Product`, `Transaction`, `AppStore`). No
/// external dependency — StoreKit ships with the OS, the same "use the native framework" choice this
/// port makes for CryptoKit (``Cryptography``) and CoreImage (``QRCodes``).
///
/// An `actor` because it caches fetched `Product` handles: the value-typed ``PurchaseProduct`` that
/// crosses the ``PurchaseManager`` boundary can't carry StoreKit's opaque `Product`, so
/// ``purchase(productID:options:)`` re-resolves it from this cache (fetching on a miss). Every operation
/// runs inside an ``Observability/Observer`` `operation` — a span whose context propagates to nested
/// async work — carrying the product/transaction identifiers and mirroring the o11y the Go Stripe
/// manager got from `observability.Observer`.
///
/// **Testing note.** StoreKit's device APIs can't be exercised hermetically from the SwiftPM CLI: a
/// faithful test needs Apple's `StoreKitTest` framework with a `.storekit` configuration and an Xcode
/// test host. Those live in the consuming app's test target; this package tests the value layer, the
/// mock, the noop, and the config/factory, and leaves live StoreKit behavior to the app.
public actor StoreKitPurchaseManager: PurchaseManager {
  /// Observability name for this component, feeding the observer's logger name and span names —
  /// mirrors the `implementationName`/`o11yName` const convention across the platform packages.
  public static let o11yName = "storekit_purchase_manager"

  private let observer: any Observer
  /// Product identifiers this app sells, from ``StoreKitConfig/productIdentifiers``. Not required —
  /// ``products(for:)`` accepts any identifiers — but retained so a caller can preload the catalog.
  public let knownProductIdentifiers: [String]
  private var productCache: [String: Product] = [:]

  public init(productIdentifiers: [String] = [], observer: any Observer) {
    self.knownProductIdentifiers = productIdentifiers
    self.observer = observer
  }

  // These methods use the observer's manual `begin`/`end` form rather than the closure form: the
  // closure form would send an `actor`-isolated closure (capturing `self`) into the nonisolated
  // generic `operation`, which Swift 6 rejects as a data-race risk. `begin` keeps everything on the
  // actor. Task-local span propagation to nested async work is therefore not automatic here — fine,
  // since no method below spawns a nested `Observer` operation.

  public func products(for identifiers: [String]) async throws -> [PurchaseProduct] {
    let op = observer.begin()
    defer { op.end() }
    op.set("storekit.requested_count", identifiers.count)
    do {
      let products = try await Product.products(for: identifiers)
      for product in products { productCache[product.id] = product }
      op.set("storekit.fetched_count", products.count)
      return products.map(PurchaseProduct.init(_:))
    } catch {
      throw op.error(error, "fetching products")
    }
  }

  public func purchase(productID: String, options: PurchaseOptions) async throws -> PurchaseResult {
    let op = observer.begin()
    defer { op.end() }
    op.set("storekit.product_id", productID)

    let product = try await resolveProduct(productID, op: op)

    var purchaseOptions: Set<Product.PurchaseOption> = []
    if let token = options.appAccountToken {
      purchaseOptions.insert(.appAccountToken(token))
    }
    if let quantity = options.quantity {
      purchaseOptions.insert(.quantity(quantity))
    }

    do {
      let result = try await product.purchase(options: purchaseOptions)
      switch result {
      case .success(let verification):
        let transaction = try Self.checkVerified(verification)
        await transaction.finish()
        op.set("storekit.transaction_id", String(transaction.id))
        return .success(Entitlement(transaction))
      case .pending:
        op.set("storekit.result", "pending")
        return .pending
      case .userCancelled:
        op.set("storekit.result", "user_cancelled")
        return .userCancelled
      @unknown default:
        throw op.error(CapitalismError.unknownPurchaseResult, "purchasing product")
      }
    } catch let error as CapitalismError {
      throw op.error(error, "purchasing product")
    } catch {
      throw op.error(
        CapitalismError.purchaseFailed(String(describing: error)), "purchasing product")
    }
  }

  public func currentEntitlements() async -> [Entitlement] {
    let op = observer.begin()
    defer { op.end() }
    var entitlements: [Entitlement] = []
    for await result in Transaction.currentEntitlements {
      // Skip unverifiable entitlements defensively rather than surfacing them — a read path
      // shouldn't grant on a transaction that failed its signature check.
      guard case .verified(let transaction) = result else { continue }
      entitlements.append(Entitlement(transaction))
    }
    op.set("storekit.entitlement_count", entitlements.count)
    return entitlements
  }

  public func restorePurchases() async throws {
    let op = observer.begin()
    defer { op.end() }
    do {
      try await AppStore.sync()
    } catch {
      throw op.error(error, "restoring purchases")
    }
  }

  public nonisolated func transactionUpdates() -> AsyncStream<TransactionUpdate> {
    AsyncStream { continuation in
      let task = Task {
        for await result in Transaction.updates {
          guard case .verified(let transaction) = result else { continue }
          // Finish the out-of-band transaction (renewal, Ask-to-Buy approval, cross-device buy) so
          // StoreKit stops re-delivering it, then hand it to the consumer.
          await transaction.finish()
          continuation.yield(TransactionUpdate(entitlement: Entitlement(transaction)))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Returns the cached `Product` for `id`, fetching it on a cache miss. Throws
  /// ``CapitalismError/productNotFound(_:)`` if the App Store has no such product.
  private func resolveProduct(_ id: String, op: any Observability.Operation) async throws -> Product {
    if let cached = productCache[id] { return cached }
    let fetched: [Product]
    do {
      fetched = try await Product.products(for: [id])
    } catch {
      throw op.error(error, "resolving product")
    }
    guard let product = fetched.first else {
      throw op.error(CapitalismError.productNotFound(id), "resolving product")
    }
    productCache[id] = product
    return product
  }

  /// Unwraps StoreKit's `VerificationResult`, throwing ``CapitalismError/unverifiedTransaction`` when
  /// the JWS signature check failed. StoreKit 2 verifies every transaction; an `.unverified` result
  /// must not be trusted or fulfilled.
  private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified:
      throw CapitalismError.unverifiedTransaction
    case .verified(let safe):
      return safe
    }
  }
}

extension PurchaseProduct {
  /// Projects StoreKit's opaque `Product` onto the value type that crosses the ``PurchaseManager``
  /// boundary.
  init(_ product: Product) {
    self.init(
      id: product.id,
      displayName: product.displayName,
      description: product.description,
      price: product.price,
      displayPrice: product.displayPrice,
      type: ProductType(product.type)
    )
  }
}

extension ProductType {
  init(_ type: Product.ProductType) {
    switch type {
    case .consumable: self = .consumable
    case .nonConsumable: self = .nonConsumable
    case .autoRenewable: self = .autoRenewable
    case .nonRenewable: self = .nonRenewable
    default: self = .nonConsumable  // `Product.ProductType` is an open struct; be conservative.
    }
  }
}

extension Entitlement {
  /// Derives an entitlement from a verified StoreKit `Transaction`. Active when it hasn't been revoked
  /// and hasn't passed its expiration (non-expiring products have no `expirationDate`).
  init(_ transaction: Transaction) {
    self.init(
      productID: transaction.productID,
      transactionID: String(transaction.id),
      purchaseDate: transaction.purchaseDate,
      expirationDate: transaction.expirationDate,
      isActive: transaction.revocationDate == nil
        && (transaction.expirationDate.map { $0 > Date() } ?? true)
    )
  }
}
