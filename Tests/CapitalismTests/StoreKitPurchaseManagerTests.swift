import Foundation
import Observability
import Testing
import os

@testable import Capitalism

/// A fake ``StoreKitClient`` for exercising ``StoreKitPurchaseManager``'s orchestration without a live
/// App Store. Each result is configurable; calls are recorded for assertions. This is the seam that
/// SVC-01/02 were previously untestable behind (see `PurchaseFinishingTests`).
private final class FakeStoreKitClient: StoreKitClient, @unchecked Sendable {
  var productsResult: Result<[PurchaseProduct], Error> = .success([])
  var purchaseResult: Result<PurchaseResult, Error> = .success(.userCancelled)
  var entitlementsResult: [Entitlement] = []
  var syncResult: Result<Void, Error> = .success(())
  var updates: [TransactionUpdate] = []

  private let recorded = OSAllocatedUnfairLock(initialState: Recorded())
  struct Recorded {
    var productsCalls: [[String]] = []
    var purchaseCalls: [(id: String, options: PurchaseOptions)] = []
    var currentEntitlementsCallCount = 0
    var syncCallCount = 0
    var transactionUpdatesCallCount = 0
  }
  var record: Recorded { recorded.withLock { $0 } }

  func products(for identifiers: [String]) async throws -> [PurchaseProduct] {
    recorded.withLock { $0.productsCalls.append(identifiers) }
    return try productsResult.get()
  }

  func purchase(productID: String, options: PurchaseOptions) async throws -> PurchaseResult {
    recorded.withLock { $0.purchaseCalls.append((productID, options)) }
    return try purchaseResult.get()
  }

  func currentEntitlements() async -> [Entitlement] {
    recorded.withLock { $0.currentEntitlementsCallCount += 1 }
    return entitlementsResult
  }

  func sync() async throws {
    recorded.withLock { $0.syncCallCount += 1 }
    try syncResult.get()
  }

  func transactionUpdates() -> AsyncStream<TransactionUpdate> {
    recorded.withLock { $0.transactionUpdatesCallCount += 1 }
    let updates = self.updates
    return AsyncStream { continuation in
      for update in updates { continuation.yield(update) }
      continuation.finish()
    }
  }
}

private func sampleProduct(_ id: String = "com.example.coins") -> PurchaseProduct {
  PurchaseProduct(
    id: id, displayName: "Coins", description: "A pile of coins",
    price: 0.99, displayPrice: "$0.99", type: .consumable)
}

private func sampleEntitlement(_ tx: String = "7") -> Entitlement {
  Entitlement(
    productID: "com.example.coins", transactionID: tx,
    purchaseDate: Date(timeIntervalSince1970: 0), expirationDate: nil, isActive: true)
}

/// REPO-10: unit tests for ``StoreKitPurchaseManager`` orchestration through the ``StoreKitClient`` seam.
@Suite("StoreKitPurchaseManager orchestration (via StoreKitClient fake)")
struct StoreKitPurchaseManagerTests {
  private func manager(_ client: FakeStoreKitClient) -> (StoreKitPurchaseManager, RecordingObserver) {
    let observer = recordingObserver(StoreKitPurchaseManager.o11yName)
    return (StoreKitPurchaseManager(observer: observer, client: client), observer)
  }

  // MARK: products

  @Test("products forwards to the client and records request/fetch counts")
  func products() async throws {
    let client = FakeStoreKitClient()
    client.productsResult = .success([sampleProduct("a"), sampleProduct("b")])
    let (mgr, observer) = manager(client)

    let result = try await mgr.products(for: ["a", "b"])
    #expect(result.map(\.id) == ["a", "b"])
    #expect(client.record.productsCalls == [["a", "b"]])

    let op = try #require(observer.operations.first)
    #expect(op.keys().contains("storekit.requested_count"))
    #expect(op.keys().contains("storekit.fetched_count"))
    #expect(op.ended)
  }

  @Test("products surfaces a client error")
  func productsError() async {
    let client = FakeStoreKitClient()
    struct Boom: Error {}
    client.productsResult = .failure(Boom())
    let (mgr, observer) = manager(client)

    await #expect(throws: (any Error).self) {
      _ = try await mgr.products(for: ["a"])
    }
    #expect(observer.operations.first?.recordedErrors.isEmpty == false)
  }

  // MARK: purchase — SVC-01 (deferred finish) + SVC-02 (typed errors)

  @Test("purchase success returns the entitlement without finishing (SVC-01)")
  func purchaseSuccessDefersFinish() async throws {
    let finished = OSAllocatedUnfairLock(initialState: false)
    let client = FakeStoreKitClient()
    client.purchaseResult = .success(
      .success(sampleEntitlement("42"), finish: { finished.withLock { $0 = true } }))
    let (mgr, observer) = manager(client)

    let result = try await mgr.purchase(productID: "com.example.coins")
    guard case .success(let entitlement, let finish) = result else {
      Issue.record("expected .success")
      return
    }
    #expect(entitlement.transactionID == "42")
    // The manager must NOT have finished the transaction — that is the caller's to do (SVC-01).
    #expect(finished.withLock { $0 } == false)
    await finish()
    #expect(finished.withLock { $0 } == true)

    #expect(observer.operations.first?.value(forKey: "storekit.transaction_id") == "42")
  }

  @Test("purchase pending / userCancelled are annotated")
  func purchaseNonSuccess() async throws {
    for (result, expected) in [
      (PurchaseResult.pending, "pending"),
      (PurchaseResult.userCancelled, "user_cancelled"),
    ] {
      let client = FakeStoreKitClient()
      client.purchaseResult = .success(result)
      let (mgr, observer) = manager(client)
      _ = try await mgr.purchase(productID: "com.example.coins")
      #expect(observer.operations.first?.value(forKey: "storekit.result") == expected)
    }
  }

  @Test("purchase passes a CapitalismError through raw and catchable (SVC-02)")
  func purchasePassesTypedThrough() async {
    let client = FakeStoreKitClient()
    client.purchaseResult = .failure(CapitalismError.unverifiedTransaction)
    let (mgr, _) = manager(client)

    await #expect(throws: CapitalismError.unverifiedTransaction) {
      _ = try await mgr.purchase(productID: "com.example.coins")
    }
  }

  @Test("purchase classifies an arbitrary error as purchaseFailed (SVC-02)")
  func purchaseClassifiesUnknown() async {
    struct StoreKitBoom: Error, CustomStringConvertible { var description: String { "kaboom" } }
    let client = FakeStoreKitClient()
    client.purchaseResult = .failure(StoreKitBoom())
    let (mgr, _) = manager(client)

    await #expect(throws: CapitalismError.purchaseFailed("kaboom")) {
      _ = try await mgr.purchase(productID: "com.example.coins")
    }
  }

  // MARK: currentEntitlements / restore / updates

  @Test("currentEntitlements forwards and records the count")
  func currentEntitlements() async throws {
    let client = FakeStoreKitClient()
    client.entitlementsResult = [sampleEntitlement("1"), sampleEntitlement("2")]
    let (mgr, observer) = manager(client)

    let entitlements = await mgr.currentEntitlements()
    #expect(entitlements.map(\.transactionID) == ["1", "2"])
    #expect(client.record.currentEntitlementsCallCount == 1)
    #expect(observer.operations.first?.value(forKey: "storekit.entitlement_count") == "2")
  }

  @Test("restorePurchases calls sync and propagates its error")
  func restore() async throws {
    let client = FakeStoreKitClient()
    let (mgr, _) = manager(client)
    try await mgr.restorePurchases()
    #expect(client.record.syncCallCount == 1)

    struct SyncBoom: Error {}
    let failing = FakeStoreKitClient()
    failing.syncResult = .failure(SyncBoom())
    let (mgr2, observer2) = manager(failing)
    await #expect(throws: (any Error).self) {
      try await mgr2.restorePurchases()
    }
    #expect(observer2.operations.first?.recordedErrors.isEmpty == false)
  }

  @Test("transactionUpdates forwards the client's stream")
  func transactionUpdates() async {
    let client = FakeStoreKitClient()
    client.updates = [
      TransactionUpdate(entitlement: sampleEntitlement("100")),
      TransactionUpdate(entitlement: sampleEntitlement("101")),
    ]
    let (mgr, _) = manager(client)

    var seen: [String] = []
    for await update in mgr.transactionUpdates() {
      seen.append(update.entitlement.transactionID)
    }
    #expect(seen == ["100", "101"])
    #expect(client.record.transactionUpdatesCallCount == 1)
  }
}
