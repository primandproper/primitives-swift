import Foundation
import Testing
import os

@testable import Capitalism

/// Regression tests for Wave 1 fixes SVC-01 (consumable purchases lost when the transaction is
/// finished before the caller persists the grant) and SVC-02 (typed ``CapitalismError`` erased into
/// ``ObservabilityError`` so callers can't catch it).
///
/// StoreKit's device APIs can't be driven hermetically from the SwiftPM CLI (a `StoreKitClient` seam is
/// deferred to a later wave), so these exercise the value-layer contract the fix rests on — that the
/// caller, not the manager, controls when a transaction is finished — plus the extractable
/// error-classification helper.
@Suite("PurchaseFinishing")
struct PurchaseFinishingTests {
  private func sampleEntitlement() -> Entitlement {
    Entitlement(
      productID: "com.example.coins", transactionID: "7",
      purchaseDate: Date(timeIntervalSince1970: 0), expirationDate: nil, isActive: true)
  }

  // MARK: SVC-01 — finishing is the caller's, and is deferred until they invoke it.

  @Test("PurchaseResult.success does not finish until the caller invokes the handle")
  func successDefersFinishing() async {
    let finished = OSAllocatedUnfairLock(initialState: false)
    let result = PurchaseResult.success(
      sampleEntitlement(), finish: { finished.withLock { $0 = true } })

    // The entitlement is available immediately, but nothing has been finished yet: a caller that
    // crashed here would still have the transaction re-delivered by StoreKit.
    guard case .success(let entitlement, let finish) = result else {
      Issue.record("expected .success")
      return
    }
    #expect(entitlement.productID == "com.example.coins")
    #expect(finished.withLock { $0 } == false)

    // Finishing happens only when the caller asks — after it has persisted the grant.
    await finish()
    #expect(finished.withLock { $0 } == true)
  }

  @Test("TransactionUpdate defers finishing to the consumer")
  func transactionUpdateDefersFinishing() async {
    let finished = OSAllocatedUnfairLock(initialState: false)
    let update = TransactionUpdate(
      entitlement: sampleEntitlement(), finish: { finished.withLock { $0 = true } })

    #expect(update.entitlement.transactionID == "7")
    #expect(finished.withLock { $0 } == false)  // yielded, not yet finished

    await update.finish()
    #expect(finished.withLock { $0 } == true)
  }

  @Test("equality ignores the finish handle")
  func equalityIgnoresFinishHandle() {
    let a = sampleEntitlement()
    // Two results with the same entitlement but different (non-Equatable) handles compare equal.
    #expect(
      PurchaseResult.success(a, finish: {}) == .success(a, finish: { await Task.yield() }))
    #expect(
      TransactionUpdate(entitlement: a, finish: {})
        == TransactionUpdate(entitlement: a, finish: { await Task.yield() }))
  }

  // MARK: SVC-02 — typed errors survive classification instead of being wrapped away.

  @Test("classifyPurchaseError passes a CapitalismError through raw")
  func classifyPassesTypedThrough() {
    for typed in [
      CapitalismError.unverifiedTransaction,
      .unknownPurchaseResult,
      .productNotFound("com.example.coins"),
      .purchaseFailed("earlier detail"),
    ] {
      #expect(StoreKitPurchaseManager.classifyPurchaseError(typed) == typed)
    }
  }

  @Test("classifyPurchaseError wraps an unknown StoreKit error as purchaseFailed, still catchable")
  func classifyWrapsUnknownAsTyped() {
    struct StoreKitBoom: Error, CustomStringConvertible { var description: String { "boom" } }

    let classified = StoreKitPurchaseManager.classifyPurchaseError(StoreKitBoom())
    #expect(classified == .purchaseFailed("boom"))

    // The regression: the classified error is a *catchable* CapitalismError, not an ObservabilityError.
    func throwing() throws { throw classified }
    #expect(throws: CapitalismError.self) { try throwing() }
    do {
      try throwing()
    } catch let error as CapitalismError {
      #expect(error == .purchaseFailed("boom"))
    } catch {
      Issue.record("expected CapitalismError, got \(type(of: error))")
    }
  }
}
