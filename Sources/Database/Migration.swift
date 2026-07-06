import Foundation

/// One ordered, versioned schema change, adapted from platform-go's `database.Migrator` seam. Go
/// delegates migration execution to an external runner (goose/darwin); this iOS client port keeps the
/// runner in-process (see ``Database/migrate(_:)``), so a migration is just its ``version``, a
/// human-readable ``name``, and the ``sql`` to run.
///
/// `sql` may contain several `;`-separated statements — the runner executes them as one script inside a
/// single transaction, so a migration applies atomically or not at all.
public struct Migration: Sendable, Equatable, Identifiable {
  /// Monotonic version number. Migrations apply in ascending `version` order; each is recorded so it is
  /// never reapplied. Must be positive and unique within a migration set.
  public let version: Int
  /// A short description, recorded in the `schema_migrations` bookkeeping table.
  public let name: String
  /// The DDL/DML to run. May contain multiple `;`-separated statements.
  public let sql: String

  public var id: Int { version }

  public init(version: Int, name: String = "", sql: String) {
    self.version = version
    self.name = name
    self.sql = sql
  }
}
