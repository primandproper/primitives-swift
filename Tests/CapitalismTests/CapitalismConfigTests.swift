import Foundation
import Observability
import Testing

@testable import Capitalism

@Suite("CapitalismConfig")
struct CapitalismConfigTests {
  private func pillars() -> Pillars {
    Pillars(logger: NoopLogger(), tracer: NoopTracer(), metrics: NoopMetricsProvider())
  }

  // MARK: resolvedProvider

  @Test("resolvedProvider trims and lowercases")
  func resolvedProvider() {
    #expect(CapitalismConfig(provider: "  StoreKit ").resolvedProvider == .storeKit)
    #expect(CapitalismConfig(provider: "REVENUECAT").resolvedProvider == .revenueCat)
    #expect(CapitalismConfig(provider: "").resolvedProvider == nil)
    #expect(CapitalismConfig(provider: "paypal").resolvedProvider == nil)
  }

  // MARK: validate

  @Test("a disabled config is always valid, whatever the provider")
  func disabledValidates() throws {
    try CapitalismConfig(provider: "", enabled: false).validate()
    try CapitalismConfig(provider: "bogus", enabled: false).validate()
  }

  @Test("an enabled StoreKit config validates without any credentials")
  func storeKitValidates() throws {
    try CapitalismConfig(provider: "storekit", enabled: true).validate()
  }

  @Test("an enabled RevenueCat config requires its credentials block")
  func revenueCatRequiresConfig() {
    #expect(throws: CapitalismConfigError.missingProviderConfig(.revenueCat)) {
      try CapitalismConfig(provider: "revenuecat", enabled: true).validate()
    }
  }

  @Test("an enabled RevenueCat config with a blank apiKey is invalid")
  func revenueCatBlankKey() {
    #expect(
      throws: CapitalismConfigError.invalidRevenueCatConfig(.missingAPIKey)
    ) {
      try CapitalismConfig(
        provider: "revenuecat", enabled: true, revenueCat: RevenueCatConfig(apiKey: "")
      ).validate()
    }
  }

  @Test("an enabled RevenueCat config with an apiKey validates")
  func revenueCatValid() throws {
    try CapitalismConfig(
      provider: "revenuecat", enabled: true, revenueCat: RevenueCatConfig(apiKey: "appl_xxx")
    ).validate()
  }

  @Test("an enabled config with an empty or unknown provider is invalid")
  func enabledUnknownProvider() {
    #expect(throws: CapitalismConfigError.unknownProvider("")) {
      try CapitalismConfig(provider: "", enabled: true).validate()
    }
    #expect(throws: CapitalismConfigError.unknownProvider("paypal")) {
      try CapitalismConfig(provider: "paypal", enabled: true).validate()
    }
  }

  // MARK: provideManager

  @Test("a disabled config provides a noop manager")
  func disabledProvidesNoop() throws {
    let manager = try CapitalismConfig(enabled: false).provideManager(pillars: pillars())
    #expect(manager is NoopPurchaseManager)
  }

  @Test("a StoreKit config provides a live StoreKit manager")
  func storeKitProvidesLive() throws {
    let manager = try CapitalismConfig(provider: "storekit", enabled: true).provideManager(
      pillars: pillars())
    #expect(manager is StoreKitPurchaseManager)
  }

  @Test("RevenueCat gets the salsa20 treatment: configured but unsupported")
  func revenueCatUnsupported() {
    #expect(throws: CapitalismError.unsupportedProvider(.revenueCat)) {
      _ = try CapitalismConfig(
        provider: "revenuecat", enabled: true, revenueCat: RevenueCatConfig(apiKey: "appl_xxx")
      ).provideManager(pillars: pillars())
    }
  }

  @Test("RevenueCat with no config throws missingProviderConfig before reaching the salsa20 refusal")
  func revenueCatMissingConfig() {
    #expect(throws: CapitalismConfigError.missingProviderConfig(.revenueCat)) {
      _ = try CapitalismConfig(provider: "revenuecat", enabled: true).provideManager(
        pillars: pillars())
    }
  }

  @Test("an enabled config with an unknown provider throws")
  func provideUnknownProvider() {
    #expect(throws: CapitalismConfigError.unknownProvider("paypal")) {
      _ = try CapitalismConfig(provider: "paypal", enabled: true).provideManager(pillars: pillars())
    }
  }

  // MARK: Codable

  @Test("decodes a full JSON config")
  func decodesFull() throws {
    let json = """
      {
        "provider": "storekit",
        "enabled": true,
        "storeKit": {"productIdentifiers": ["com.example.pro"]},
        "revenueCat": {"apiKey": "appl_xxx"}
      }
      """
    let config = try JSONDecoder().decode(CapitalismConfig.self, from: Data(json.utf8))
    #expect(config.provider == "storekit")
    #expect(config.enabled)
    #expect(config.storeKit?.productIdentifiers == ["com.example.pro"])
    #expect(config.revenueCat?.apiKey == "appl_xxx")
  }

  @Test("a partial JSON config decodes to zero values")
  func decodesPartial() throws {
    let config = try JSONDecoder().decode(CapitalismConfig.self, from: Data("{}".utf8))
    #expect(config.provider.isEmpty)
    #expect(!config.enabled)
    #expect(config.storeKit == nil)
    #expect(config.revenueCat == nil)
  }

  @Test("round-trips through JSON")
  func roundTrip() throws {
    let original = CapitalismConfig(
      provider: "storekit", enabled: true, storeKit: StoreKitConfig(productIdentifiers: ["a"]),
      revenueCat: RevenueCatConfig(apiKey: "k"))
    let decoded = try JSONDecoder().decode(
      CapitalismConfig.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
  }
}
