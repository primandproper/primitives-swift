import Foundation
import Testing

@testable import Capitalism

@Suite("StoreKitConfig")
struct StoreKitConfigTests {
  @Test("decodes the JSON shape")
  func decodes() throws {
    let config = try JSONDecoder().decode(
      StoreKitConfig.self,
      from: Data(#"{"productIdentifiers":["com.example.a","com.example.b"]}"#.utf8))
    #expect(config.productIdentifiers == ["com.example.a", "com.example.b"])
  }

  @Test("a missing productIdentifiers key decodes to an empty list")
  func missingKey() throws {
    let config = try JSONDecoder().decode(StoreKitConfig.self, from: Data("{}".utf8))
    #expect(config.productIdentifiers.isEmpty)
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = StoreKitConfig(productIdentifiers: ["com.example.pro"])
    let decoded = try JSONDecoder().decode(
      StoreKitConfig.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }
}
