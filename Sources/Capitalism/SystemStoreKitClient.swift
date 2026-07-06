import Foundation
import StoreKit

/// The live ``StoreKitClient``, backed by Apple's built-in **StoreKit 2**. This is where every
/// `import StoreKit` touchpoint lives — `Product`/`Transaction`/`AppStore`, the JWS verification, and
/// the projection onto this module's StoreKit-free value types — so ``StoreKitPurchaseManager`` stays a
/// hermetically testable orchestrator.
///
/// An `actor` because it caches fetched `Product` handles: the value-typed ``PurchaseProduct`` that
/// crosses the seam can't carry StoreKit's opaque `Product`, so ``purchase(productID:options:)``
/// re-resolves it from this cache (fetching on a miss).
///
/// **Testing note.** StoreKit's device APIs can't be exercised hermetically from the SwiftPM CLI: a
/// faithful test needs Apple's `StoreKitTest` framework with a `.storekit` configuration and an Xcode
/// test host. Those live in the consuming app's test target; this package tests the manager's
/// orchestration through a fake ``StoreKitClient``, plus the value layer, the mock, and the noop.
public actor SystemStoreKitClient: StoreKitClient {
  private var productCache: [String: Product] = [:]

  public init() {}

  public func products(for identifiers: [String]) async throws -> [PurchaseProduct] {
    let products = try await Product.products(for: identifiers)
    for product in products { productCache[product.id] = product }
    return products.map(PurchaseProduct.init(_:))
  }

  public func purchase(productID: String, options: PurchaseOptions) async throws -> PurchaseResult {
    let product = try await resolveProduct(productID)

    var purchaseOptions: Set<Product.PurchaseOption> = []
    if let token = options.appAccountToken {
      purchaseOptions.insert(.appAccountToken(token))
    }
    if let quantity = options.quantity {
      purchaseOptions.insert(.quantity(quantity))
    }

    let result = try await product.purchase(options: purchaseOptions)
    switch result {
    case .success(let verification):
      let transaction = try Self.checkVerified(verification)
      // Hand the caller a `finish` handle rather than finishing here: StoreKit keeps re-delivering the
      // transaction until it is finished, so finishing before the caller has persisted the grant would
      // permanently lose a paid consumable if the app crashed in between (SVC-01).
      return .success(Entitlement(transaction), finish: { await transaction.finish() })
    case .pending:
      return .pending
    case .userCancelled:
      return .userCancelled
    @unknown default:
      throw CapitalismError.unknownPurchaseResult
    }
  }

  public func currentEntitlements() async -> [Entitlement] {
    var entitlements: [Entitlement] = []
    for await result in Transaction.currentEntitlements {
      // Skip unverifiable entitlements defensively rather than surfacing them — a read path shouldn't
      // grant on a transaction that failed its signature check.
      guard case .verified(let transaction) = result else { continue }
      entitlements.append(Entitlement(transaction))
    }
    return entitlements
  }

  public func sync() async throws {
    try await AppStore.sync()
  }

  public nonisolated func transactionUpdates() -> AsyncStream<TransactionUpdate> {
    AsyncStream { continuation in
      let task = Task {
        for await result in Transaction.updates {
          guard case .verified(let transaction) = result else { continue }
          // Hand the out-of-band transaction to the consumer with a `finish` handle rather than
          // finishing it here. StoreKit keeps re-delivering until finished, so the consumer finishes
          // only after persisting the grant; finishing first would drop the update on a crash.
          continuation.yield(
            TransactionUpdate(
              entitlement: Entitlement(transaction), finish: { await transaction.finish() }))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Returns the cached `Product` for `id`, fetching it on a cache miss. Throws
  /// ``CapitalismError/productNotFound(_:)`` if the App Store has no such product.
  private func resolveProduct(_ id: String) async throws -> Product {
    if let cached = productCache[id] { return cached }
    let fetched = try await Product.products(for: [id])
    guard let product = fetched.first else {
      throw CapitalismError.productNotFound(id)
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
