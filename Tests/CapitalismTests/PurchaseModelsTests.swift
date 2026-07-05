import Foundation
import Testing

@testable import Capitalism

@Suite("PurchaseModels")
struct PurchaseModelsTests {
  @Test("PurchaseProduct round-trips through JSON")
  func productRoundTrip() throws {
    let original = PurchaseProduct(
      id: "com.example.pro", displayName: "Pro", description: "Everything unlocked",
      price: Decimal(string: "9.99")!, displayPrice: "$9.99", type: .autoRenewable)
    let decoded = try JSONDecoder().decode(
      PurchaseProduct.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }

  @Test("Entitlement round-trips through JSON, including a nil expiration")
  func entitlementRoundTrip() throws {
    let original = Entitlement(
      productID: "com.example.pro", transactionID: "42",
      purchaseDate: Date(timeIntervalSince1970: 1_700_000_000), expirationDate: nil, isActive: true)
    let decoded = try JSONDecoder().decode(Entitlement.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
    #expect(decoded.id == "42")  // Identifiable keys off transactionID
  }

  @Test("ProductType decodes from its lowerCamelCase raw values")
  func productTypeRawValues() {
    #expect(ProductType(rawValue: "consumable") == .consumable)
    #expect(ProductType(rawValue: "nonConsumable") == .nonConsumable)
    #expect(ProductType(rawValue: "autoRenewable") == .autoRenewable)
    #expect(ProductType(rawValue: "nonRenewable") == .nonRenewable)
    #expect(ProductType(rawValue: "bogus") == nil)
  }

  @Test("PurchaseResult equality distinguishes cases and payloads")
  func purchaseResultEquality() {
    let a = Entitlement(
      productID: "p", transactionID: "1", purchaseDate: Date(timeIntervalSince1970: 0),
      expirationDate: nil, isActive: true)
    let b = Entitlement(
      productID: "p", transactionID: "2", purchaseDate: Date(timeIntervalSince1970: 0),
      expirationDate: nil, isActive: true)
    #expect(PurchaseResult.success(a) == .success(a))
    #expect(PurchaseResult.success(a) != .success(b))
    #expect(PurchaseResult.pending != .userCancelled)
    #expect(PurchaseResult.success(a) != .pending)
  }

  @Test("PurchaseOptions defaults are nil")
  func purchaseOptionsDefaults() {
    let options = PurchaseOptions()
    #expect(options.appAccountToken == nil)
    #expect(options.quantity == nil)
  }
}
