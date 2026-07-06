import Foundation

/// A handle rooted at a sandbox boundary, ported from platform-go's `Dir`/`OpenDir`/`NewDir`
/// (`dir.go`). Its methods take file names relative to that root, so the leading path is supplied once:
/// `Dir(root: .documents)` then `try dir.chunks("stuff.txt", size: 100)` reads
/// `<documents>/stuff.txt`.
///
/// **This is the one place the port deliberately diverges in behavior, not just shape.** Go's
/// `Dir.Chdir`/`Dir.Sub` navigate freely to any ancestor or sibling directory (`dir_test.go`'s "Chdir
/// navigates to the parent directory" is a documented, intended capability) — appropriate when `Dir`
/// merely wraps a path string for a CLI/server process. On iOS, ``DirRoot/documents`` and
/// ``DirRoot/appGroup(_:)`` name the app's *actual* sandbox boundary, so letting a `Dir` walk upward out
/// of it would defeat the sandbox rather than just being a navigation convenience. This `Dir`:
///   * has no mutating `Chdir` at all;
///   * resolves every name via ``resolve(_:)``, which rejects `..` segments, an absolute override, or a
///     symlink that would land outside the root;
///   * only exposes ``sub(_:)`` (Go's non-mutating `Sub`), and only for descending — a rejected
///     `resolve(_:)` makes escaping through `sub` impossible too, since `sub` resolves before
///     constructing the child `Dir`.
public struct Dir: Sendable {
  /// The root directory, resolved to an absolute, symlink-resolved path.
  public let path: String

  private let reader: any FileReader

  /// Opens a handle rooted at `root`.
  /// - Throws: ``FilesError/notADirectory(_:)`` if `root` can't be resolved to an existing directory on
  ///   this device.
  public init(root: DirRoot, reader: any FileReader = LiveFileReader()) throws {
    let resolved = try root.resolve().resolvingSymlinksInPath()
    try Dir.requireDirectory(at: resolved.path)
    self.path = resolved.path
    self.reader = reader
  }

  private init(path: String, reader: any FileReader) {
    self.path = path
    self.reader = reader
  }

  /// Resolves `name` against ``path``, rejecting anything that would escape it.
  /// - Throws: ``FilesError/pathEscapesRoot(_:)`` if the resolved path is not equal to, or nested under,
  ///   ``path`` — this rejects `..` segments that walk above the root, an absolute `name` that overrides
  ///   it entirely, and a symlink that resolves outside it.
  public func resolve(_ name: String) throws -> String {
    let base = URL(fileURLWithPath: path, isDirectory: true)
    let candidate = URL(fileURLWithPath: name, isDirectory: false, relativeTo: base)
      .standardizedFileURL
    let candidatePath = candidate.resolvingSymlinksInPath().path

    guard candidatePath == path || candidatePath.hasPrefix(path + "/") else {
      throw FilesError.pathEscapesRoot(name)
    }

    return candidatePath
  }

  /// The non-mutating, sandbox-respecting form of Go's `Sub`: returns a new handle rooted at `name`
  /// (resolved against this ``Dir``'s root), sharing its reader. Unlike Go's `Sub`, `name` can only
  /// resolve to somewhere at or under the current root — see ``resolve(_:)``.
  /// - Throws: ``FilesError/pathEscapesRoot(_:)`` (via ``resolve(_:)``) or ``FilesError/notADirectory(_:)``
  ///   if the resolved path isn't a directory.
  public func sub(_ name: String) throws -> Dir {
    let resolved = try resolve(name)
    try Dir.requireDirectory(at: resolved)
    return Dir(path: resolved, reader: reader)
  }

  /// Opens `name` (relative to ``path``) and yields each of its lines. Mirrors Go's `Dir.Lines`.
  public func lines(_ name: String) throws -> AsyncThrowingStream<String, Error> {
    try reader.lines(atPath: resolve(name))
  }

  /// Opens `name` (relative to ``path``) and yields chunks of up to `size` lines. Mirrors Go's
  /// `Dir.Chunks` (and, via ``FileReader``'s collapsed seam, `Dir.StreamChunks`).
  public func chunks(_ name: String, size: Int) throws -> AsyncThrowingStream<[String], Error> {
    try reader.chunks(atPath: resolve(name), size: size)
  }

  /// Opens `name` (relative to ``path``) and returns up to `count` lines after skipping `offset`.
  /// Mirrors Go's `Dir.SliceLines`.
  public func sliceLines(_ name: String, offset: Int, count: Int) async throws -> [String] {
    try await reader.sliceLines(atPath: resolve(name), offset: offset, count: count)
  }

  private static func requireDirectory(at path: String) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw FilesError.notADirectory(path)
    }
  }
}
