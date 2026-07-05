import Testing

@testable import Capitalism

@Suite("CapitalismProvider")
struct CapitalismProviderTests {
  @Test("raw values are the lowercase provider keys")
  func rawValues() {
    #expect(CapitalismProvider.storeKit.rawValue == "storekit")
    #expect(CapitalismProvider.revenueCat.rawValue == "revenuecat")
  }

  @Test("CapitalismError carries a readable description")
  func errorDescriptions() {
    #expect(
      CapitalismError.unsupportedProvider(.revenueCat).errorDescription?.contains("revenuecat")
        == true)
    #expect(
      CapitalismError.productNotFound("com.example.pro").errorDescription?.contains("com.example.pro")
        == true)
    #expect(CapitalismError.unverifiedTransaction.errorDescription != nil)
    #expect(CapitalismError.unknownPurchaseResult.errorDescription != nil)
    #expect(CapitalismError.purchaseFailed("nope").errorDescription?.contains("nope") == true)
  }
}
