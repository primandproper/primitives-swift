import CircuitBreaking
import Foundation
import Observability
import Testing

@testable import Uploads

@Suite("UploadsConfig")
struct UploadsConfigTests {
  private func decode(_ json: String) throws -> UploadsConfig {
    try JSONDecoder().decode(UploadsConfig.self, from: Data(json.utf8))
  }

  @Test("an empty object decodes to zero values")
  func emptyDecodes() throws {
    let cfg = try decode("{}")
    #expect(cfg.filesystem == nil)
    #expect(cfg.bucketPrefix == "")
    #expect(cfg.bucketName == "")
    // The embedded breaker config decodes to its zero value (defaults applied later).
    #expect(cfg.circuitBreaker == CircuitBreakerConfig())
  }

  @Test("a partial object fills only the present fields")
  func partialDecodes() throws {
    let cfg = try decode(#"{"bucketName":"avatars","filesystem":{"rootDirectory":"/tmp/up"}}"#)
    #expect(cfg.bucketName == "avatars")
    #expect(cfg.bucketPrefix == "")
    #expect(cfg.filesystem?.rootDirectory == "/tmp/up")
    // Unset directory mode resolves to the 0700 default.
    #expect(cfg.filesystem?.resolvedDirectoryMode == 0o700)
  }

  @Test("the embedded circuit breaker config decodes from Go's wire keys")
  func embeddedBreakerDecodes() throws {
    let json = #"""
      {"circuitBreakerConfig":{"name":"uploads","circuitBreakerErrorPercentage":50,
      "circuitBreakerMinimumOccurrenceThreshold":10}}
      """#
    let cfg = try decode(json)
    #expect(cfg.circuitBreaker.name == "uploads")
    #expect(cfg.circuitBreaker.errorRate == 50)
    #expect(cfg.circuitBreaker.minimumSampleThreshold == 10)
  }

  @Test("round-trips through encode/decode")
  func roundTrips() throws {
    let original = UploadsConfig(
      filesystem: FilesystemConfig(rootDirectory: "/data", directoryMode: 0o755),
      bucketPrefix: "p/",
      bucketName: "b",
      circuitBreaker: CircuitBreakerConfig(name: "cb", errorRate: 25, minimumSampleThreshold: 5))
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(UploadsConfig.self, from: encoded)
    #expect(decoded == original)
  }

  @Test("makeFileManagerUploader requires a root directory")
  func requiresRoot() {
    #expect(throws: UploadsError.missingRootDirectory) {
      _ = try UploadsConfig().makeFileManagerUploader(pillars: .noop)
    }
    #expect(throws: UploadsError.missingRootDirectory) {
      _ = try UploadsConfig(filesystem: FilesystemConfig(rootDirectory: ""))
        .makeFileManagerUploader(pillars: .noop)
    }
  }

  @Test("makeFileManagerUploader builds a uploader rooted at the configured directory")
  func buildsFileManager() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("cfg-\(UUID().uuidString)", isDirectory: true)
    let cfg = UploadsConfig(filesystem: FilesystemConfig(rootDirectory: root.path))
    let uploader = try cfg.makeFileManagerUploader(pillars: .noop)
    #expect(uploader.root.path == root.standardizedFileURL.path)
  }

  @Test("makePresignedUploader builds a live uploader")
  func buildsPresigned() {
    let uploader = UploadsConfig().makePresignedUploader(pillars: .noop)
    _ = uploader  // constructing without throwing is the assertion; behavior is covered elsewhere.
  }
}
