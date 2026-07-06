import DurationWire
import Foundation
import Observability

/// The database configuration, adapted from platform-go's `databasecfg.Config`.
///
/// The Go config is provider-agnostic (Postgres/MySQL/SQLite connection details, read/write pools, ping
/// retries, otel toggles). This iOS client port targets the local SQLite backend only, so the shape
/// collapses to: where the file lives (``path`` under an optionally app-group-shared container, or
/// in-memory), whether to run migrations, and the per-connection PRAGMA knobs. ``busyTimeout`` keeps the
/// Go-wire `time.Duration` shape — a bare nanosecond integer over JSON (see ``Duration/wholeNanoseconds``).
///
/// Decoding is lenient: every key is optional and a missing key falls back to the Go zero value / the
/// default here, so a partial `{}` object decodes cleanly (mirroring how partial JSON unmarshals into a
/// Go struct). See the `{}`-decode test.
public struct DatabaseConfig: Codable, Sendable, Equatable {
  /// The database file name or path. Empty (the default) opens a private in-memory database — ideal for
  /// tests and rebuild-on-launch stores. An absolute path (leading `/`) is used verbatim; a bare file
  /// name is resolved under the sandbox container (see ``appGroupIdentifier``). The literal `:memory:`
  /// is honored as-is. Analogue of Go's `ConnectionDetails.Database` for the SQLite provider.
  public var path: String
  /// When true, open `:memory:` regardless of ``path``.
  public var inMemory: Bool
  /// A shared app-group container identifier. When set, a relative ``path`` resolves under that group's
  /// container (so an app and its extensions share one database); otherwise it resolves under the app's
  /// Documents directory.
  public var appGroupIdentifier: String?
  /// Whether ``DatabaseConfig/makeDatabase(migrations:pillars:)`` runs the supplied migrations. Mirrors
  /// Go's `RunMigrations`.
  public var runMigrations: Bool
  /// Whether to enable `PRAGMA foreign_keys` on the connection. Defaults to `true`; Go sets it in the
  /// DSN for every pooled connection.
  public var foreignKeys: Bool
  /// Whether to enable WAL journaling (`PRAGMA journal_mode=WAL`). Ignored for in-memory databases.
  /// Defaults to `true`, matching Go's sqlite client.
  public var walJournalMode: Bool
  /// How long SQLite waits on a locked database before returning `SQLITE_BUSY` (`PRAGMA busy_timeout`).
  /// Carried as a Go-wire nanosecond `Duration`. Defaults to 5s.
  public var busyTimeout: Duration

  public static let defaultBusyTimeout: Duration = .seconds(5)

  public init(
    path: String = "",
    inMemory: Bool = false,
    appGroupIdentifier: String? = nil,
    runMigrations: Bool = false,
    foreignKeys: Bool = true,
    walJournalMode: Bool = true,
    busyTimeout: Duration = DatabaseConfig.defaultBusyTimeout
  ) {
    self.path = path
    self.inMemory = inMemory
    self.appGroupIdentifier = appGroupIdentifier
    self.runMigrations = runMigrations
    self.foreignKeys = foreignKeys
    self.walJournalMode = walJournalMode
    self.busyTimeout = busyTimeout
  }

  private enum CodingKeys: String, CodingKey {
    case path
    case inMemory
    case appGroupIdentifier
    case runMigrations
    case foreignKeys
    case walJournalMode
    case busyTimeout
  }

  /// Missing keys decode to defaults rather than failing, matching how a partial JSON object unmarshals
  /// into a Go struct. ``busyTimeout`` is read as a bare nanosecond integer (Go's `time.Duration` wire
  /// form) rather than Swift's structured `Duration` encoding.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
    inMemory = try container.decodeIfPresent(Bool.self, forKey: .inMemory) ?? false
    appGroupIdentifier = try container.decodeIfPresent(String.self, forKey: .appGroupIdentifier)
    runMigrations = try container.decodeIfPresent(Bool.self, forKey: .runMigrations) ?? false
    foreignKeys = try container.decodeIfPresent(Bool.self, forKey: .foreignKeys) ?? true
    walJournalMode = try container.decodeIfPresent(Bool.self, forKey: .walJournalMode) ?? true
    if let nanos = try container.decodeIfPresent(Int64.self, forKey: .busyTimeout) {
      busyTimeout = Duration(wireNanoseconds: nanos)
    } else {
      busyTimeout = DatabaseConfig.defaultBusyTimeout
    }
  }

  /// Encodes ``busyTimeout`` back to the Go-wire nanosecond integer so a round-trip stays wire-compatible.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(path, forKey: .path)
    try container.encode(inMemory, forKey: .inMemory)
    try container.encodeIfPresent(appGroupIdentifier, forKey: .appGroupIdentifier)
    try container.encode(runMigrations, forKey: .runMigrations)
    try container.encode(foreignKeys, forKey: .foreignKeys)
    try container.encode(walJournalMode, forKey: .walJournalMode)
    try container.encode(busyTimeout.wholeNanoseconds, forKey: .busyTimeout)
  }

  /// The concrete filename handed to `sqlite3_open`: `:memory:` for an in-memory database, an absolute
  /// path verbatim, or a relative ``path`` resolved under the app-group / Documents container.
  public func resolvedPath() -> String {
    if inMemory || path.isEmpty { return ":memory:" }
    if path == ":memory:" || path.hasPrefix("/") { return path }
    return containerDirectory().appendingPathComponent(path).path
  }

  /// The sandbox directory a relative ``path`` resolves under: the shared app-group container when
  /// ``appGroupIdentifier`` is set and resolvable, otherwise the app's Documents directory (falling back
  /// to a temporary directory when even that is unavailable, e.g. under some test hosts).
  func containerDirectory() -> URL {
    let fileManager = FileManager.default
    if let group = appGroupIdentifier,
      let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: group)
    {
      return url
    }
    if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
      return documents
    }
    return fileManager.temporaryDirectory
  }
}

extension DatabaseConfig {
  /// Opens the configured SQLite database and, when ``runMigrations`` is set, applies `migrations`. The
  /// iOS analogue of Go's `databasecfg.ProvideDatabase`, which builds the client and conditionally runs
  /// the injected migrator.
  public func makeDatabase(
    migrations: [Migration] = [],
    pillars: Pillars = .noop
  ) async throws -> SQLiteDatabase {
    let database = try SQLiteDatabase(config: self, pillars: pillars)
    if runMigrations && !migrations.isEmpty {
      _ = try await database.migrate(migrations)
    }
    return database
  }
}
