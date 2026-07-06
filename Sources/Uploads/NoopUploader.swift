import Foundation

/// A no-op ``Uploader``, ported from platform-go's `uploads/noop`. The safe default when no storage is
/// configured: ``save(_:data:options:)`` and ``delete(_:)`` discard, ``read(_:)`` returns empty data, and
/// ``exists(_:)`` always reports `false` — mirroring Go's `noop.UploadManager`, whose `Save` drains the
/// reader, `Open` returns an empty reader, and `Exists` returns `false`.
public struct NoopUploader: Uploader {
  public init() {}

  public func save(_ path: String, data: Data, options: SaveOptions) async throws {}

  public func read(_ path: String) async throws -> Data { Data() }

  public func delete(_ path: String) async throws {}

  public func exists(_ path: String) async throws -> Bool { false }
}
