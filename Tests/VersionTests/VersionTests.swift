import Foundation
import Testing

@testable import Version

@Suite("Info.from(infoDictionary:)")
struct InfoFromBundleTests {
  @Test("maps CFBundleShortVersionString to version and CFBundleVersion to buildNumber")
  func mapsBundleKeys() {
    let info = Info.from(infoDictionary: [
      "CFBundleShortVersionString": "1.2.3",
      "CFBundleVersion": "42",
    ])

    #expect(info.version == "1.2.3")
    #expect(info.buildNumber == "42")
  }

  @Test("VCS fields have no bundle source and report \"unknown\"")
  func vcsFieldsUnknown() {
    let info = Info.from(infoDictionary: [
      "CFBundleShortVersionString": "1.0.0",
      "CFBundleVersion": "7",
    ])

    #expect(info.commitHash == "unknown")
    #expect(info.commitTime == "unknown")
    #expect(info.buildTime == "unknown")
  }

  @Test("missing bundle keys fall back to \"unknown\"")
  func missingKeysUnknown() {
    let info = Info.from(infoDictionary: nil)

    #expect(info.version == "unknown")
    #expect(info.buildNumber == "unknown")
  }
}

@Suite("Info init normalization")
struct InfoInitTests {
  @Test("preserves populated fields")
  func preservesValues() {
    let info = Info(
      version: "v1.2.3", buildNumber: "100", commitHash: "abc123",
      commitTime: "2026-01-01T00:00:00Z", buildTime: "2026-01-02T00:00:00Z")

    #expect(info.version == "v1.2.3")
    #expect(info.buildNumber == "100")
    #expect(info.commitHash == "abc123")
    #expect(info.commitTime == "2026-01-01T00:00:00Z")
    #expect(info.buildTime == "2026-01-02T00:00:00Z")
  }

  @Test("records empty fields as \"unknown\", mirroring Go's Get")
  func emptyBecomesUnknown() {
    let info = Info(version: "")

    #expect(info.version == "unknown")
    #expect(info.buildNumber == "unknown")
    #expect(info.commitHash == "unknown")
    #expect(info.commitTime == "unknown")
    #expect(info.buildTime == "unknown")
  }
}

@Suite("Info JSON")
struct InfoJSONTests {
  @Test("encodes Go-compatible snake_case keys")
  func snakeCaseKeys() throws {
    let info = Info(
      version: "v9.9.9", buildNumber: "9", commitHash: "deadbeef",
      commitTime: "2026-03-03T00:00:00Z", buildTime: "2026-03-04T00:00:00Z")

    let json = String(decoding: try info.jsonData(), as: UTF8.self)

    #expect(json.contains("\"version\""))
    #expect(json.contains("\"build_number\""))
    #expect(json.contains("\"commit_hash\""))
    #expect(json.contains("\"commit_time\""))
    #expect(json.contains("\"build_time\""))
  }

  @Test("emits keys in stable, alphabetically sorted order")
  func sortedKeyOrdering() throws {
    let info = Info(
      version: "v9.9.9", buildNumber: "9", commitHash: "deadbeef",
      commitTime: "2026-03-03T00:00:00Z", buildTime: "2026-03-04T00:00:00Z")

    let json = String(decoding: try info.jsonData(), as: UTF8.self)

    // `.sortedKeys` orders keys alphabetically; verify the emitted positions follow suit.
    let order = ["build_number", "build_time", "commit_hash", "commit_time", "version"]
    let positions = try order.map { key -> String.Index in
      let range = try #require(json.range(of: "\"\(key)\""))
      return range.lowerBound
    }
    #expect(positions == positions.sorted())

    // Ordering must also be deterministic across repeated encodes.
    #expect(try info.jsonData() == info.jsonData())
  }

  @Test("round-trips through Codable")
  func roundTrips() throws {
    let info = Info(
      version: "v1.0.0", buildNumber: "1", commitHash: "abc", commitTime: "t1", buildTime: "t2")

    let decoded = try JSONDecoder().decode(Info.self, from: info.jsonData())

    #expect(decoded == info)
  }

  @Test("decodes a Go payload lacking build_number, defaulting it to \"unknown\"")
  func decodesGoPayload() throws {
    let payload = """
      {"version":"v1.2.3","commit_hash":"abc123","commit_time":"t1","build_time":"t2"}
      """

    let info = try JSONDecoder().decode(Info.self, from: Data(payload.utf8))

    #expect(info.version == "v1.2.3")
    #expect(info.commitHash == "abc123")
    #expect(info.buildNumber == "unknown")
  }

  @Test("writeJSON emits round-trippable bytes to a text stream")
  func writeJSONToStream() throws {
    let info = Info(version: "v2.0.0", buildNumber: "5")

    var out = ""
    try info.writeJSON(to: &out)

    let decoded = try JSONDecoder().decode(Info.self, from: Data(out.utf8))
    #expect(decoded == info)
  }
}
