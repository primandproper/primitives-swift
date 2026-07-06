import CircuitBreaking
import Foundation
import Observability

/// The uploads configuration, ported from platform-go's `objectstorage.Config` — trimmed to the two
/// backends this port keeps (local filesystem + presigned remote) and embedding a
/// ``CircuitBreaking/CircuitBreakerConfig`` for the remote backend exactly as Go does.
///
/// **Dropped from Go's Config.** The `provider` selector and its cloud values (S3/GCS/R2/Backblaze/memory)
/// plus the `r2`/`backblazeB2` sub-configs are gone — no cloud SDK ships on the device. What remains maps
/// one-to-one: ``filesystem`` (Go's `FilesystemConfig`), ``bucketPrefix`` (a key prefix), ``bucketName``
/// (retained for telemetry naming), and ``circuitBreaker`` (Go's embedded `circuitbreakingcfg.Config`).
///
/// Decoding is lenient (`decodeIfPresent ?? <zero>`, matching ``LLM/LLMConfig`` and
/// ``FeatureFlags/LaunchDarklyConfig``): a `{}` or partial JSON object decodes successfully to Go's zero
/// values. Wire keys match Go: `filesystem`, `bucketPrefix`, `bucketName`, `circuitBreakerConfig`.
public struct UploadsConfig: Codable, Sendable, Equatable {
  /// The local filesystem backend config, when a deployment uses it. `nil` when unconfigured.
  public var filesystem: FilesystemConfig?
  /// A prefix prepended to every object key (Go's `BucketPrefix`). Empty means none.
  public var bucketPrefix: String
  /// The logical bucket name, retained only for telemetry naming (Go's `BucketName`).
  public var bucketName: String
  /// The circuit breaker guarding the remote backend.
  public var circuitBreaker: CircuitBreakerConfig

  public init(
    filesystem: FilesystemConfig? = nil,
    bucketPrefix: String = "",
    bucketName: String = "",
    circuitBreaker: CircuitBreakerConfig = CircuitBreakerConfig()
  ) {
    self.filesystem = filesystem
    self.bucketPrefix = bucketPrefix
    self.bucketName = bucketName
    self.circuitBreaker = circuitBreaker
  }

  private enum CodingKeys: String, CodingKey {
    case filesystem
    case bucketPrefix
    case bucketName
    case circuitBreaker = "circuitBreakerConfig"
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    filesystem = try c.decodeIfPresent(FilesystemConfig.self, forKey: .filesystem)
    bucketPrefix = try c.decodeIfPresent(String.self, forKey: .bucketPrefix) ?? ""
    bucketName = try c.decodeIfPresent(String.self, forKey: .bucketName) ?? ""
    circuitBreaker =
      try c.decodeIfPresent(CircuitBreakerConfig.self, forKey: .circuitBreaker)
      ?? CircuitBreakerConfig()
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(filesystem, forKey: .filesystem)
    try c.encode(bucketPrefix, forKey: .bucketPrefix)
    try c.encode(bucketName, forKey: .bucketName)
    try c.encode(circuitBreaker, forKey: .circuitBreaker)
  }
}

extension UploadsConfig {
  /// Builds the local ``FileManagerUploader``, the analogue of Go's `NewUploadManager(...)` for the
  /// filesystem provider. Throws ``UploadsError/missingRootDirectory`` when ``filesystem`` (or its root)
  /// is absent — the port of Go's `ErrNilConfig` / required-`RootDirectory` validation.
  public func makeFileManagerUploader(pillars: Pillars) throws -> FileManagerUploader {
    guard let filesystem, !filesystem.rootDirectory.isEmpty else {
      throw UploadsError.missingRootDirectory
    }
    return FileManagerUploader(
      root: URL(fileURLWithPath: filesystem.rootDirectory, isDirectory: true),
      directoryMode: filesystem.resolvedDirectoryMode,
      pillars: pillars)
  }

  /// Builds the live remote ``URLSessionPresignedUploader`` with a breaker from ``circuitBreaker`` — the
  /// analogue of Go's remote `NewUploadManager(...)`, minus the cloud client.
  public func makePresignedUploader(
    pillars: Pillars,
    session: URLSession = URLSession(configuration: .ephemeral)
  ) -> URLSessionPresignedUploader {
    URLSessionPresignedUploader(
      circuitBreaker: circuitBreaker, pillars: pillars, session: session)
  }
}
