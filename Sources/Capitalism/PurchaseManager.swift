/// Handles in-app purchases on the client, ported from platform-go's `capitalism.PaymentManager`
/// (`payment_manager.go`) — but **reshaped**, because the Go interface is server-shaped and iOS is not.
///
/// The Go origin (`HandleEventWebhook`, `CreateCustomer`, `CreatePaymentIntent`, `CreateSubscription`)
/// describes a *backend* talking to Stripe: it receives webhooks, mints customers, and creates payment
/// intents whose `ClientSecret` is handed *down* to a device SDK to complete. On iOS the device is the
/// active party, so the seam inverts. The method mapping:
///
/// | Go (`PaymentManager`) | here (`PurchaseManager`) | why |
/// |---|---|---|
/// | `CreatePaymentIntent` | ``purchase(productID:options:)`` | the device buys directly via StoreKit |
/// | `CreateSubscription` | ``purchase(productID:options:)`` (auto-renewable product) | same call, subscription product |
/// | `CreateCustomer` | ``PurchaseOptions/appAccountToken`` | no server customer; the App Store account *is* the customer, tied to a backend user via the account token |
/// | `HandleEventWebhook` | ``transactionUpdates()`` | the client observes StoreKit's verified feed; RevenueCat/Apple's *server* eats the webhooks |
/// | — | ``products(for:)``, ``currentEntitlements()``, ``restorePurchases()`` | client affordances the server-shaped Go interface had no need for |
///
/// Per this port's settled conventions (see `PORTING.md`), `context.Context` is dropped and every
/// method is `async throws` so a real StoreKit-backed conformer can suspend and fail without Go's
/// explicit `ctx`/`error` plumbing.
public protocol PurchaseManager: Sendable {
  /// Fetches products from the App Store by identifier. Unknown identifiers are simply absent from the
  /// result (StoreKit does not error on them). Mirrors StoreKit's `Product.products(for:)`.
  func products(for identifiers: [String]) async throws -> [PurchaseProduct]

  /// Purchases the product with the given identifier, presenting the system purchase sheet. Returns the
  /// outcome; on ``PurchaseResult/success(_:)`` the underlying transaction has already been verified and
  /// finished. The client analogue of Go's `CreatePaymentIntent`/`CreateSubscription`.
  func purchase(productID: String, options: PurchaseOptions) async throws -> PurchaseResult

  /// The set of entitlements the user currently holds, read from StoreKit's current-entitlements feed.
  /// Non-throwing: unverifiable transactions are skipped rather than surfaced. Replaces the server-side
  /// "look up this customer's subscriptions" query.
  func currentEntitlements() async -> [Entitlement]

  /// Restores purchases by syncing with the App Store (StoreKit's `AppStore.sync()`), for the
  /// "Restore Purchases" button flows Apple requires. After it returns, ``currentEntitlements()``
  /// reflects any restored entitlements.
  func restorePurchases() async throws

  /// A stream of transactions arriving outside a direct purchase — renewals, revocations, Ask-to-Buy
  /// approvals, cross-device purchases. The on-device replacement for Go's `HandleEventWebhook`. The
  /// conformer finishes each transaction before yielding it. The stream ends when its consuming task is
  /// cancelled.
  func transactionUpdates() -> AsyncStream<TransactionUpdate>
}

extension PurchaseManager {
  /// Convenience overload for a purchase with no options. Swift protocol requirements can't carry
  /// default argument values, so this fills the role a defaulted `options` parameter would.
  public func purchase(productID: String) async throws -> PurchaseResult {
    try await purchase(productID: productID, options: PurchaseOptions())
  }
}
