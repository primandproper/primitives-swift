/// A no-op ``PurchaseManager``, ported from platform-go's `capitalism/noop` package. The safe default
/// when payments are disabled (or an unrecognized provider is configured), so purchase call sites don't
/// have to nil-check a manager that may not exist.
///
/// Every method returns the empty/neutral value: no products, no entitlements, an immediately-finished
/// update stream, and a ``PurchaseResult/userCancelled`` for any purchase attempt (nothing was bought).
public struct NoopPurchaseManager: PurchaseManager {
  public init() {}

  public func products(for identifiers: [String]) -> [PurchaseProduct] { [] }

  public func purchase(productID: String, options: PurchaseOptions) -> PurchaseResult {
    .userCancelled
  }

  public func currentEntitlements() -> [Entitlement] { [] }

  public func restorePurchases() {}

  public func transactionUpdates() -> AsyncStream<TransactionUpdate> {
    AsyncStream { $0.finish() }
  }
}
