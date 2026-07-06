import Foundation

/// The sandbox boundary a ``Dir`` is rooted at.
///
/// Go's `OpenDir`/`NewDir` take an arbitrary path string — appropriate for a CLI/server process with no
/// sandbox of its own. On iOS, the meaningful roots are the app's actual sandbox directories, so this
/// port replaces the raw path string with a small closed set (plus ``custom(_:)`` for tests and any
/// root this set doesn't anticipate).
public enum DirRoot: Sendable, Equatable {
  /// The app's documents directory (`FileManager.default.urls(for: .documentDirectory, in:
  /// .userDomainMask)`), backed up by iCloud/Finder file sharing when the app opts in.
  case documents
  /// The shared container for the given app-group identifier
  /// (`FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`), for data shared
  /// between an app and its extensions.
  case appGroup(String)
  /// An arbitrary directory URL, for tests (a `FileManager.default.temporaryDirectory` subdirectory) or
  /// a root this enum doesn't otherwise name (e.g. the caches directory).
  case custom(URL)

  func resolve() throws -> URL {
    switch self {
    case .documents:
      guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      else {
        throw FilesError.notADirectory("documents directory is unavailable on this device")
      }
      return url

    case .appGroup(let identifier):
      guard
        let url = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: identifier)
      else {
        throw FilesError.notADirectory("app group container unavailable: \(identifier)")
      }
      return url

    case .custom(let url):
      return url
    }
  }
}
