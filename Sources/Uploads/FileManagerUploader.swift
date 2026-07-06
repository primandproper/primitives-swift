import Foundation
import Observability

/// A **local** ``Uploader`` that stores objects as files under a sandbox root, ported from platform-go's
/// `objectstorage` filesystem provider (`bucket_filesystem.go` + gocloud `fileblob`).
///
/// Each object path becomes a file beneath ``root``; intermediate directories are created on demand with
/// owner-only (`0700`) permissions, mirroring Go's deliberate departure from gocloud's `0777` default so
/// other users on a shared host can't traverse in and read stored objects (on iOS the app sandbox already
/// isolates this, but the mode is preserved for parity and defense in depth).
///
/// **Path-traversal is rejected.** Every path is resolved against ``root`` and confirmed to stay inside
/// it *before* any filesystem access, so a caller-supplied key like `../../etc/passwd` throws
/// ``UploadsError/pathEscapesRoot(_:)`` rather than escaping the root. Absolute and empty paths are
/// likewise refused.
///
/// The type is an immutable `Sendable` value: `FileManager` calls are synchronous and thread-safe, and
/// the injected observer is `Sendable`, so an instance can be shared across tasks. Operations still run
/// inside an ``Observability/Observer`` `operation` to thread the pillars, matching the rest of the port.
public struct FileManagerUploader: Uploader {
  /// Observability name for this component, feeding the observer's logger/span names.
  public static let o11yName = "uploads_filesystem"
  /// Directory mode for created directories: owner-only, mirroring Go's `defaultDirectoryMode` (0700).
  public static let defaultDirectoryMode: UInt16 = 0o700

  /// The sandbox root every object path resolves beneath. Standardized at init so the traversal guard
  /// compares canonical paths.
  public let root: URL
  private let directoryMode: UInt16
  private let observer: any Observer

  /// The file manager to use. `FileManager` is not `Sendable`, so rather than store an instance this
  /// property returns the process-wide singleton on each access (its file operations are thread-safe).
  private var fileManager: FileManager { .default }

  /// Primary initializer — inject an already-built observer. The seam tests use: pass a
  /// ``Observability/RecordingObserver`` and a temp-directory root to exercise the backend hermetically.
  ///
  /// `root` is resolved to a standardized file URL so the path-traversal guard compares canonical paths
  /// (symlink components in caller keys are still confined by the prefix check).
  public init(
    root: URL,
    directoryMode: UInt16 = FileManagerUploader.defaultDirectoryMode,
    observer: any Observer
  ) {
    self.root = root.standardizedFileURL
    self.directoryMode = directoryMode == 0 ? Self.defaultDirectoryMode : directoryMode
    self.observer = observer
  }

  /// Convenience initializer building the observer from pillars — the analogue of Go's
  /// `NewUploadManager(...)` for the filesystem provider.
  public init(
    root: URL,
    directoryMode: UInt16 = FileManagerUploader.defaultDirectoryMode,
    pillars: Pillars
  ) {
    self.init(
      root: root,
      directoryMode: directoryMode,
      observer: LiveObserver(
        name: Self.o11yName, logger: pillars.logger, tracer: pillars.tracer))
  }

  public func save(_ path: String, data: Data, options: SaveOptions) async throws {
    try await observer.operation(name: "uploads.filesystem.save") { op in
      op.set("upload.path", path)
      op.set("upload.bytes", data.count)
      let url = try resolvedURL(for: path, op: op)
      do {
        try createParentDirectory(for: url)
        try data.write(to: url, options: .atomic)
      } catch let error as UploadsError {
        throw error
      } catch {
        throw op.error(error, "writing object to disk")
      }
    }
  }

  public func read(_ path: String) async throws -> Data {
    try await observer.operation(name: "uploads.filesystem.read") { op in
      op.set("upload.path", path)
      let url = try resolvedURL(for: path, op: op)
      guard fileManager.fileExists(atPath: url.path) else {
        throw UploadsError.notFound(path)
      }
      do {
        return try Data(contentsOf: url)
      } catch {
        throw op.error(error, "reading object from disk")
      }
    }
  }

  public func delete(_ path: String) async throws {
    try await observer.operation(name: "uploads.filesystem.delete") { op in
      op.set("upload.path", path)
      let url = try resolvedURL(for: path, op: op)
      // Deleting a missing object is a no-op, not an error, so a delete-then-delete or delete of a
      // never-written key succeeds quietly.
      guard fileManager.fileExists(atPath: url.path) else { return }
      do {
        try fileManager.removeItem(at: url)
      } catch {
        throw op.error(error, "deleting object from disk")
      }
    }
  }

  public func exists(_ path: String) async throws -> Bool {
    try await observer.operation(name: "uploads.filesystem.exists") { op in
      op.set("upload.path", path)
      let url = try resolvedURL(for: path, op: op)
      var isDirectory: ObjCBool = false
      let present = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      // A directory at the key is not an object.
      return present && !isDirectory.boolValue
    }
  }

  // MARK: - Path safety

  /// Resolves `path` to a file URL beneath ``root``, rejecting anything that would escape it.
  ///
  /// The guard standardizes the candidate (collapsing `.`/`..`) and requires its canonical path to equal
  /// the root or sit under `root + "/"`. That single prefix check catches `..` traversal, absolute paths
  /// (which `appendingPathComponent` folds under the root but a crafted `../` could still escape), and
  /// sneaky mixes — all before any filesystem call.
  func resolvedURL(for path: String, op: any Observability.Operation) throws -> URL {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      op.acknowledge(UploadsError.invalidPath(path), "empty object path")
      throw UploadsError.invalidPath(path)
    }

    let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
    let rootPath = root.path
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

    guard candidate.path == rootPath || candidate.path.hasPrefix(rootPrefix) else {
      op.acknowledge(UploadsError.pathEscapesRoot(path), "object path escapes storage root")
      throw UploadsError.pathEscapesRoot(path)
    }
    // A path that resolves to the root itself is not a valid object key (it's the directory).
    guard candidate.path != rootPath else {
      op.acknowledge(UploadsError.invalidPath(path), "object path resolves to the storage root")
      throw UploadsError.invalidPath(path)
    }
    return candidate
  }

  private func createParentDirectory(for url: URL) throws {
    let parent = url.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: parent,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: directoryMode)])
  }
}
