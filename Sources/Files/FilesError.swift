import Foundation

/// Errors thrown by the ``Files`` module.
///
/// The first five cases mirror platform-go's `files` package sentinel errors (`errors.go`) and
/// `decodeBytes`'s empty-input rejection (`decode.go`). ``pathEscapesRoot(_:)`` and
/// ``notADirectory(_:)`` have no exact Go analogue: Go's `Dir` allows free navigation (so it never needs
/// a "you tried to escape" error), and its `resolveDir` folds "not a directory" into a generic wrapped
/// `os.Stat` error rather than a typed case. See ``Dir`` for why this port's sandbox-rooted `Dir` needs
/// both as first-class, typed failures.
public enum FilesError: Error, Equatable, Sendable {
  /// A chunk size of zero or less was requested. Mirrors Go's `ErrNonPositiveChunkSize`.
  case nonPositiveChunkSize
  /// A windowed read's offset was negative. Mirrors Go's `ErrNegativeOffset`.
  case negativeOffset
  /// A windowed read's count was negative. Mirrors Go's `ErrNegativeCount`.
  case negativeCount
  /// A windowed read's offset landed at or past the end of the input. Mirrors Go's `ErrOffsetBeyondEOF`.
  case offsetBeyondEOF
  /// `decode`/`decodeFile` was given empty input, which no supported encoding treats as a valid
  /// document. Mirrors Go's `errors.ErrEmptyInputParameter` as used by `decodeBytes`.
  case emptyInput
  /// A name resolved against a ``Dir``'s root would escape it (via a `..` segment, an absolute
  /// override, or a symlink). See ``Dir/resolve(_:)``.
  case pathEscapesRoot(String)
  /// The resolved path is not a directory, or the requested ``DirRoot`` (documents directory / app-group
  /// container) could not be located on this device.
  case notADirectory(String)
}

extension FilesError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .nonPositiveChunkSize:
      return "chunk size must be greater than zero"
    case .negativeOffset:
      return "offset must not be negative"
    case .negativeCount:
      return "count must not be negative"
    case .offsetBeyondEOF:
      return "offset is at or beyond end of input"
    case .emptyInput:
      return "input is empty"
    case .pathEscapesRoot(let name):
      return "path escapes sandbox root: \(name)"
    case .notADirectory(let path):
      return "not a directory: \(path)"
    }
  }
}
