import Foundation
import Testing

@testable import HealthCheck

@Suite("HealthCheckConfig")
struct HealthCheckConfigTests {
  @Test("an empty JSON object decodes to Go's zero-value defaults")
  func emptyObjectDecodesToDefaults() throws {
    let config = try JSONDecoder().decode(HealthCheckConfig.self, from: Data("{}".utf8))
    #expect(config.checkTimeout == HealthCheckRegistry.defaultCheckTimeout)
    #expect(config.diskSpace.minimumFreeBytes == DiskSpaceChecker.defaultMinimumFreeBytes)
  }

  @Test("a partial JSON object fills only the missing fields with defaults")
  func partialObjectFillsMissingFields() throws {
    let json = Data(#"{"diskSpace":{"minimumFreeBytes":123}}"#.utf8)
    let config = try JSONDecoder().decode(HealthCheckConfig.self, from: json)
    #expect(config.checkTimeout == HealthCheckRegistry.defaultCheckTimeout)
    #expect(config.diskSpace.minimumFreeBytes == 123)
  }

  @Test(
    "checkTimeout round-trips as a bare nanosecond integer, matching Go's time.Duration wire shape")
  func checkTimeoutRoundTripsAsNanoseconds() throws {
    let config = HealthCheckConfig(checkTimeout: .seconds(2))
    let data = try JSONEncoder().encode(config)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(object?["checkTimeout"] as? Int64 == 2_000_000_000)

    let decoded = try JSONDecoder().decode(HealthCheckConfig.self, from: data)
    #expect(decoded == config)
  }

  @Test("default init matches the documented Go-equivalent zero values")
  func defaultInitMatchesZeroValues() {
    let config = HealthCheckConfig()
    #expect(config.checkTimeout == .seconds(5))
    #expect(config.diskSpace.minimumFreeBytes == 50 * 1024 * 1024)
  }
}
