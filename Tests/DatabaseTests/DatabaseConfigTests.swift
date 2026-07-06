import Foundation
import Testing

@testable import Database

@Suite("DatabaseConfig")
struct DatabaseConfigTests {
  // MARK: lenient decoding

  @Test("an empty object decodes to Go zero values / defaults")
  func emptyObjectDecodes() throws {
    let config = try JSONDecoder().decode(DatabaseConfig.self, from: Data("{}".utf8))
    #expect(config.path == "")
    #expect(config.inMemory == false)
    #expect(config.appGroupIdentifier == nil)
    #expect(config.runMigrations == false)
    #expect(config.foreignKeys == true)
    #expect(config.walJournalMode == true)
    #expect(config.busyTimeout == DatabaseConfig.defaultBusyTimeout)
  }

  @Test("a partial object decodes present keys and defaults the rest")
  func partialObjectDecodes() throws {
    let json = #"{"path":"app.db","runMigrations":true,"foreignKeys":false}"#
    let config = try JSONDecoder().decode(DatabaseConfig.self, from: Data(json.utf8))
    #expect(config.path == "app.db")
    #expect(config.runMigrations == true)
    #expect(config.foreignKeys == false)
    // Untouched keys keep their defaults.
    #expect(config.walJournalMode == true)
    #expect(config.busyTimeout == DatabaseConfig.defaultBusyTimeout)
  }

  @Test("busyTimeout decodes from a bare Go-wire nanosecond integer")
  func busyTimeoutDecodesFromNanoseconds() throws {
    // 2s == 2_000_000_000 ns, the form Go marshals time.Duration in.
    let json = #"{"busyTimeout":2000000000}"#
    let config = try JSONDecoder().decode(DatabaseConfig.self, from: Data(json.utf8))
    #expect(config.busyTimeout == .seconds(2))
  }

  @Test("encoding round-trips busyTimeout as nanoseconds")
  func encodeRoundTripsNanoseconds() throws {
    let config = DatabaseConfig(busyTimeout: .milliseconds(1500))
    let data = try JSONEncoder().encode(config)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(object?["busyTimeout"] as? Int64 == 1_500_000_000)

    let decoded = try JSONDecoder().decode(DatabaseConfig.self, from: data)
    #expect(decoded == config)
  }

  // MARK: resolvedPath

  @Test("resolvedPath returns :memory: for empty or in-memory configs")
  func resolvedPathInMemory() {
    #expect(DatabaseConfig().resolvedPath() == ":memory:")
    #expect(DatabaseConfig(inMemory: true).resolvedPath() == ":memory:")
    #expect(DatabaseConfig(path: ":memory:").resolvedPath() == ":memory:")
    #expect(DatabaseConfig(path: "app.db", inMemory: true).resolvedPath() == ":memory:")
  }

  @Test("resolvedPath passes an absolute path through verbatim")
  func resolvedPathAbsolute() {
    #expect(DatabaseConfig(path: "/tmp/app.db").resolvedPath() == "/tmp/app.db")
  }

  @Test("resolvedPath resolves a relative path under the container directory")
  func resolvedPathRelative() {
    let config = DatabaseConfig(path: "app.db")
    let resolved = config.resolvedPath()
    #expect(resolved.hasSuffix("/app.db"))
    #expect(resolved != "app.db")
  }

  // MARK: Duration wire helper

  @Test("Duration wire helpers convert nanoseconds and milliseconds")
  func durationWireHelpers() {
    #expect(Duration(wireNanoseconds: 5_000_000_000) == .seconds(5))
    #expect(Duration.seconds(3).wholeNanoseconds == 3_000_000_000)
    #expect(Duration.milliseconds(250).wholeMilliseconds == 250)
  }
}
