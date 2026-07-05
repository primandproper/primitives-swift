import Foundation

/// Build and VCS metadata, ported from platform-go's `version/version.go`.
///
/// **Port deviation — where the values come from.** In Go this data is injected at link time via
/// `-ldflags -X version.Version=…` into mutable package-level vars. iOS apps have no
/// linker-ldflags equivalent and don't read the process environment, so the idiomatic source is
/// the app bundle: `CFBundleShortVersionString` (the marketing version, → ``version``) and
/// `CFBundleVersion` (the build number, → ``buildNumber`` — an iOS-specific field with no Go
/// analogue). The VCS fields (``commitHash``, ``commitTime``, ``buildTime``) have no bundle
/// source — nothing bakes a git commit into an `Info.plist` — so ``current`` reports them as
/// `"unknown"`. A build phase that generates a Swift constants file can still inject real values
/// through ``init(version:buildNumber:commitHash:commitTime:buildTime:)``, which is the closest
/// analogue to ldflags.
///
/// Empty fields are recorded as `"unknown"`, mirroring Go's `Get`. Decoding tolerates a
/// Go-authored payload that omits `build_number`.
public struct Info: Sendable, Equatable, Codable {
  /// Value used for any field left empty. Matches Go's `unknownVersion`.
  static let unknown = "unknown"

  /// Marketing version, from `CFBundleShortVersionString` (e.g. "1.2.3"). Go's `Version`.
  public let version: String
  /// Build number, from `CFBundleVersion`. iOS-specific; no Go analogue.
  public let buildNumber: String
  /// VCS commit hash. No iOS bundle source; `"unknown"` unless injected. Go's `CommitHash`.
  public let commitHash: String
  /// VCS commit timestamp. No iOS bundle source; `"unknown"` unless injected. Go's `CommitTime`.
  public let commitTime: String
  /// Build timestamp. No iOS bundle source; `"unknown"` unless injected. Go's `BuildTime`.
  public let buildTime: String

  enum CodingKeys: String, CodingKey {
    case version
    case buildNumber = "build_number"
    case commitHash = "commit_hash"
    case commitTime = "commit_time"
    case buildTime = "build_time"
  }

  /// Creates version info, recording any empty field as `"unknown"` (mirrors Go's `Get`).
  public init(
    version: String,
    buildNumber: String = "",
    commitHash: String = "",
    commitTime: String = "",
    buildTime: String = ""
  ) {
    self.version = Info.normalize(version)
    self.buildNumber = Info.normalize(buildNumber)
    self.commitHash = Info.normalize(commitHash)
    self.commitTime = Info.normalize(commitTime)
    self.buildTime = Info.normalize(buildTime)
  }

  /// Decodes tolerantly: absent keys (e.g. a Go payload without `build_number`) and empty strings
  /// become `"unknown"` via the designated initializer.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      version: try container.decodeIfPresent(String.self, forKey: .version) ?? "",
      buildNumber: try container.decodeIfPresent(String.self, forKey: .buildNumber) ?? "",
      commitHash: try container.decodeIfPresent(String.self, forKey: .commitHash) ?? "",
      commitTime: try container.decodeIfPresent(String.self, forKey: .commitTime) ?? "",
      buildTime: try container.decodeIfPresent(String.self, forKey: .buildTime) ?? ""
    )
  }

  private static func normalize(_ value: String) -> String {
    value.isEmpty ? unknown : value
  }
}

extension Info {
  /// The running app's version info, read from `Bundle.main`. The iOS analogue of Go's `Get`.
  public static var current: Info {
    from(infoDictionary: Bundle.main.infoDictionary)
  }

  /// Builds `Info` from an `Info.plist`-style dictionary. Split out from ``current`` so the
  /// bundle-key mapping is testable without depending on the test bundle's own keys.
  static func from(infoDictionary: [String: Any]?) -> Info {
    Info(
      version: infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
      buildNumber: infoDictionary?["CFBundleVersion"] as? String ?? ""
    )
  }
}

extension Info {
  /// Pretty-printed JSON with Go-compatible snake_case keys. Mirrors the 2-space indented output
  /// of Go's `WriteJSON`.
  public func jsonData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    return try encoder.encode(self)
  }

  /// Writes pretty-printed JSON to `target` — the `TextOutputStream` analogue of Go's
  /// `WriteJSON(io.Writer)`.
  public func writeJSON<Target: TextOutputStream>(to target: inout Target) throws {
    target.write(String(decoding: try jsonData(), as: UTF8.self))
  }

  /// Writes pretty-printed JSON to standard output. Mirrors Go's `WriteJSONToStdout`, for CLI use.
  public func writeJSONToStdout() throws {
    var stdout = StandardOutput()
    try writeJSON(to: &stdout)
  }
}

/// A `TextOutputStream` over the process's standard output, so ``Info/writeJSONToStdout()`` reaches
/// the real `stdout` (unbuffered, unlike `print`), matching Go's `os.Stdout`.
private struct StandardOutput: TextOutputStream {
  mutating func write(_ string: String) {
    try? FileHandle.standardOutput.write(contentsOf: Data(string.utf8))
  }
}
