import Foundation

/// Errors surfaced by ``Database`` conformers, adapted from platform-go's `database` error family.
///
/// Go leans on wrapped errors from `database/sql` plus the sentinels `ErrDatabaseNotReady` and
/// `ErrUserAlreadyExists`. This iOS client port drops the multi-backend surface (see ``Database``) and
/// keeps a small, `Equatable` set so a caller can `switch`/`catch` the way Go compares with `errors.Is`.
public enum DatabaseError: Error, Equatable, Sendable {
  /// The SQLite database file could not be opened. Carries the engine's message. Analogue of Go's
  /// "connecting to sqlite database" wrap.
  case open(String)
  /// The underlying SQLite C library reported a failure preparing, binding, or stepping a statement.
  /// Carries the engine's message.
  case backend(String)
  /// The ``DatabaseConfig`` failed validation. Carries the human-readable reason.
  case invalidConfig(String)
  /// A migration failed to apply; the enclosing transaction was rolled back. Carries the failing
  /// migration's version and the engine message.
  case migration(String)
  /// The database is not ready for queries. Mirrors Go's `ErrDatabaseNotReady`.
  case notReady

  public var description: String {
    switch self {
    case .open(let message): return "opening database: \(message)"
    case .backend(let message): return "database backend error: \(message)"
    case .invalidConfig(let reason): return "invalid database config: \(reason)"
    case .migration(let message): return "migration failed: \(message)"
    case .notReady: return "database is not ready yet"
    }
  }
}

extension DatabaseError: LocalizedError {
  public var errorDescription: String? { description }
}
