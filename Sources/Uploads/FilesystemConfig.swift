import Foundation

/// Configuration for the local filesystem backend, ported from platform-go's
/// `objectstorage.FilesystemConfig`.
///
/// Go tags each field with `env:` and `json:`; per the settled port architecture iOS apps don't configure
/// from the environment, so only the JSON contract survives — the coding keys (`rootDirectory`,
/// `directoryMode`) match Go's exactly. Decoding is lenient (`decodeIfPresent ?? <zero>`) so a `{}` or
/// partial object decodes to Go's zero value.
public struct FilesystemConfig: Codable, Sendable, Equatable {
  /// The sandbox root directory objects are stored beneath.
  public var rootDirectory: String
  /// The POSIX mode for directories the backend creates. Zero defaults to `0o700` (owner-only), mirroring
  /// Go's `FilesystemConfig.directoryMode()`.
  public var directoryMode: UInt16

  public init(rootDirectory: String = "", directoryMode: UInt16 = 0) {
    self.rootDirectory = rootDirectory
    self.directoryMode = directoryMode
  }

  /// The configured directory mode, or the `0o700` default when unset. Mirrors Go's `directoryMode()`.
  public var resolvedDirectoryMode: UInt16 {
    directoryMode == 0 ? FileManagerUploader.defaultDirectoryMode : directoryMode
  }

  private enum CodingKeys: String, CodingKey {
    case rootDirectory
    case directoryMode
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    rootDirectory = try c.decodeIfPresent(String.self, forKey: .rootDirectory) ?? ""
    directoryMode = try c.decodeIfPresent(UInt16.self, forKey: .directoryMode) ?? 0
  }
}
