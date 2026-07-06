import Foundation
import os

/// A unique temporary directory for filesystem-touching tests (Files/Uploads/Cache/Database-style),
/// created under `FileManager.default.temporaryDirectory` and torn down on ``remove()``.
///
/// Uniqueness comes from a process-scoped monotonic counter rather than randomness, keeping the port's
/// no-`Math.random()`/no-`Date.now()` determinism rule: within a run each directory name is a pure
/// function of the process id and the number of directories created before it. The path itself is never
/// something a test should assert on, so the process id (stable within a run, distinct across concurrent
/// runs) only serves to keep leftovers from a crashed prior run from colliding.
public struct TemporaryDirectory: Sendable {
  /// The directory's URL. Guaranteed to exist until ``remove()`` is called.
  public let url: URL

  private static let counter = OSAllocatedUnfairLock(initialState: 0)

  /// Creates a fresh, empty directory named after `label` plus a unique suffix.
  ///
  /// - Parameter label: A human-readable prefix for the directory name, to make stray leftovers legible.
  public init(label: String = "TestSupport") throws {
    let sequence = Self.counter.withLock { (count: inout Int) -> Int in
      count += 1
      return count
    }
    let name = "\(label)-\(ProcessInfo.processInfo.processIdentifier)-\(sequence)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      name, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.url = directory
  }

  /// A URL for `name` inside this directory. Does not create anything on disk.
  public func file(_ name: String) -> URL {
    url.appendingPathComponent(name)
  }

  /// Writes `data` to `name` inside this directory and returns the file's URL.
  @discardableResult
  public func write(_ data: Data, to name: String) throws -> URL {
    let destination = file(name)
    try data.write(to: destination)
    return destination
  }

  /// Deletes the directory and everything under it. Safe to call more than once.
  public func remove() throws {
    let manager = FileManager.default
    guard manager.fileExists(atPath: url.path) else { return }
    try manager.removeItem(at: url)
  }
}

/// Runs `body` with a freshly created ``TemporaryDirectory`` and removes it afterward, even if `body`
/// throws — the scoped analogue of Go's `t.TempDir()`.
public func withTemporaryDirectory<Result>(
  label: String = "TestSupport", _ body: (URL) throws -> Result
) throws -> Result {
  let directory = try TemporaryDirectory(label: label)
  defer { try? directory.remove() }
  return try body(directory.url)
}
