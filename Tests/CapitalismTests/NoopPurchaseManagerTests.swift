import Testing

@testable import Capitalism

@Suite("NoopPurchaseManager")
struct NoopPurchaseManagerTests {
  // Held as `any PurchaseManager` (not the concrete struct) so each call goes through the
  // async-throwing protocol requirement, matching how a real app would inject this manager.
  private var manager: any PurchaseManager { NoopPurchaseManager() }

  @Test("products returns an empty list")
  func products() async throws {
    let result = try await manager.products(for: ["com.example.pro"])
    #expect(result.isEmpty)
  }

  @Test("purchase returns userCancelled (nothing was bought)")
  func purchase() async throws {
    let result = try await manager.purchase(productID: "com.example.pro")
    #expect(result == .userCancelled)
  }

  @Test("currentEntitlements returns an empty list")
  func currentEntitlements() async {
    let result = await manager.currentEntitlements()
    #expect(result.isEmpty)
  }

  @Test("restorePurchases returns without throwing")
  func restorePurchases() async throws {
    try await manager.restorePurchases()
  }

  @Test("transactionUpdates yields nothing and finishes immediately")
  func transactionUpdates() async {
    var count = 0
    for await _ in manager.transactionUpdates() { count += 1 }
    #expect(count == 0)
  }
}
