import Foundation

/// Reads and writes objects in a storage backend — ported from platform-go's `uploads.UploadManager`.
///
/// Go's interface is `Save(ctx, path, io.Reader, ...SaveOption)` / `Open(ctx, path) io.ReadCloser` /
/// `Delete(ctx, path)` / `Exists(ctx, path) bool`. The Swift port keeps the four operations but trades
/// Go's streaming `io.Reader`/`io.ReadCloser` for `Data`: a client upload/download is a bounded
/// in-memory blob (a picked photo, a document), not an unbounded server stream, and `Data` keeps the
/// seam `Sendable` and easy to double. The methods are `async` because the conforming backends are
/// actors / perform I/O, and `throws` mirrors Go's returned `error`.
///
/// Conformers: ``FileManagerUploader`` (local sandbox-root backend), ``NoopUploader`` (safe default),
/// and actor ``UploaderMock`` (test double). The remote presigned-URL path is a *separate* seam —
/// ``PresignedUploader`` — because uploading bytes to a server-minted URL is a different operation from
/// keyed local storage.
public protocol Uploader: Sendable {
  /// Writes `data` to the object at `path`. `options` carries optional stored metadata; see
  /// ``SaveOptions`` for which backends honor it.
  func save(_ path: String, data: Data, options: SaveOptions) async throws

  /// Returns the full contents of the object at `path`. Throws ``UploadsError/notFound(_:)`` when no
  /// object exists there.
  func read(_ path: String) async throws -> Data

  /// Removes the object at `path`. Deleting a missing object is a no-op (matching gocloud's
  /// idempotent-ish delete semantics for the filesystem backend), not an error.
  func delete(_ path: String) async throws

  /// Reports whether an object exists at `path`.
  func exists(_ path: String) async throws -> Bool
}

extension Uploader {
  /// Saves `data` with default (empty) options — the common case, the analogue of Go's `SaveFile`
  /// convenience helper.
  public func save(_ path: String, data: Data) async throws {
    try await save(path, data: data, options: SaveOptions())
  }
}
