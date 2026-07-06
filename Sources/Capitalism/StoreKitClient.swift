import Foundation

/// The seam between ``StoreKitPurchaseManager`` and Apple's StoreKit APIs.
///
/// StoreKit's device types (`Product`, `Transaction`, `VerificationResult`) can't be constructed or
/// driven hermetically from the SwiftPM CLI, which is why the manager's orchestration used to be
/// untestable (see the note in `PurchaseFinishingTests`). This protocol lifts every StoreKit touchpoint
/// behind an interface that traffics **only** in this module's StoreKit-free value types, so:
///   * the live conformer (``SystemStoreKitClient``) owns all the `import StoreKit` projection — the
///     `Product` cache, JWS verification, and `Transaction → Entitlement` mapping; and
///   * the manager keeps just the cross-cutting logic — observability spans and the SVC-02 typed-error
///     classification — which a **fake** conformer can now exercise end to end in a unit test.
///
/// Method shapes mirror ``PurchaseManager`` (minus the observability), so the manager is a thin
/// orchestrator over this seam. `transactionUpdates()` is a synchronous requirement (matching
/// ``PurchaseManager/transactionUpdates()``) so an actor conformer implements it `nonisolated`.
public protocol StoreKitClient: Sendable {
  /// Fetches products by identifier and projects them to ``PurchaseProduct``. Mirrors StoreKit's
  /// `Product.products(for:)` (unknown identifiers are simply absent, not an error).
  func products(for identifiers: [String]) async throws -> [PurchaseProduct]

  /// Runs a purchase: resolves the product, maps `options`, verifies the resulting transaction, and
  /// returns the outcome. On ``PurchaseResult/success(_:finish:)`` the transaction is verified but
  /// **not** finished — the `finish` handle defers that to the caller (SVC-01). Throws the underlying
  /// failure raw (a ``CapitalismError`` or a StoreKit error) for the manager to classify.
  func purchase(productID: String, options: PurchaseOptions) async throws -> PurchaseResult

  /// The user's current entitlements, already filtered to verified transactions. Mirrors
  /// `Transaction.currentEntitlements`.
  func currentEntitlements() async -> [Entitlement]

  /// Syncs with the App Store (StoreKit's `AppStore.sync()`), for "Restore Purchases".
  func sync() async throws

  /// A stream of out-of-band verified transactions (renewals, revocations, Ask-to-Buy approvals,
  /// cross-device buys), each carrying a deferred `finish` handle. Mirrors `Transaction.updates`.
  func transactionUpdates() -> AsyncStream<TransactionUpdate>
}
