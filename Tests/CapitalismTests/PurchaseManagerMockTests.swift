import Foundation
import Testing

@testable import Capitalism

@Suite("PurchaseManagerMock")
struct PurchaseManagerMockTests {
  private func sampleProduct(_ id: String = "com.example.pro") -> PurchaseProduct {
    PurchaseProduct(
      id: id, displayName: "Pro", description: "Pro tier", price: 4.99, displayPrice: "$4.99",
      type: .autoRenewable)
  }

  private func sampleEntitlement(_ id: String = "com.example.pro") -> Entitlement {
    Entitlement(
      productID: id, transactionID: "1", purchaseDate: Date(timeIntervalSince1970: 0),
      expirationDate: nil, isActive: true)
  }

  @Test("an unset handler returns the empty/neutral value and still records the call")
  func defaultsAreQuiet() async throws {
    let mock = PurchaseManagerMock()

    #expect(try await mock.products(for: ["a", "b"]).isEmpty)
    #expect(try await mock.purchase(productID: "x") == .userCancelled)
    #expect(await mock.currentEntitlements().isEmpty)
    try await mock.restorePurchases()

    #expect(await mock.productsCalls == [["a", "b"]])
    #expect(await mock.purchaseCalls.count == 1)
    #expect(await mock.currentEntitlementsCallCount == 1)
    #expect(await mock.restorePurchasesCallCount == 1)
  }

  @Test("handlers drive the return values")
  func handlersDrive() async throws {
    let product = sampleProduct()
    let entitlement = sampleEntitlement()
    let mock = PurchaseManagerMock(
      productsHandler: { _ in [product] },
      purchaseHandler: { _, _ in .success(entitlement) },
      currentEntitlementsHandler: { [entitlement] },
      restorePurchasesHandler: {}
    )

    #expect(try await mock.products(for: ["com.example.pro"]) == [product])
    #expect(try await mock.purchase(productID: "com.example.pro") == .success(entitlement))
    #expect(await mock.currentEntitlements() == [entitlement])
    try await mock.restorePurchases()
  }

  @Test("purchase records the productID and options passed")
  func purchaseRecordsArgs() async throws {
    let mock = PurchaseManagerMock()
    let token = UUID()
    _ = try await mock.purchase(
      productID: "com.example.pro", options: PurchaseOptions(appAccountToken: token, quantity: 2))

    let calls = await mock.purchaseCalls
    #expect(calls.count == 1)
    #expect(calls.first?.productID == "com.example.pro")
    #expect(calls.first?.options == PurchaseOptions(appAccountToken: token, quantity: 2))
  }

  @Test("a throwing handler propagates")
  func throwingHandler() async {
    struct Boom: Error {}
    let mock = PurchaseManagerMock(restorePurchasesHandler: { throw Boom() })
    await #expect(throws: Boom.self) {
      try await mock.restorePurchases()
    }
  }

  @Test("transactionUpdates uses its handler and counts calls")
  func transactionUpdates() async {
    let entitlement = sampleEntitlement()
    let mock = PurchaseManagerMock(
      transactionUpdatesHandler: {
        AsyncStream { continuation in
          continuation.yield(TransactionUpdate(entitlement: entitlement))
          continuation.finish()
        }
      })

    var received: [TransactionUpdate] = []
    for await update in mock.transactionUpdates() { received.append(update) }

    #expect(received == [TransactionUpdate(entitlement: entitlement)])
    #expect(mock.transactionUpdatesCallCount == 1)
  }
}
