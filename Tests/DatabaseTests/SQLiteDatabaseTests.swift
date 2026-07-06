import Foundation
import Observability
import Testing

@testable import Database

@Suite("SQLiteDatabase")
struct SQLiteDatabaseTests {
  private func inMemory() throws -> SQLiteDatabase {
    try SQLiteDatabase(config: DatabaseConfig(inMemory: true))
  }

  private static let migrations: [Migration] = [
    Migration(
      version: 1, name: "create_widgets",
      sql: "CREATE TABLE widgets (id INTEGER PRIMARY KEY, name TEXT NOT NULL, weight REAL);"),
    Migration(
      version: 2, name: "add_widget_archived",
      sql: "ALTER TABLE widgets ADD COLUMN archived INTEGER NOT NULL DEFAULT 0;"),
  ]

  // MARK: migrations

  @Test("migrate applies pending migrations in order and records the version")
  func migrateAppliesAndRecordsVersion() async throws {
    let db = try inMemory()
    #expect(try await db.currentVersion() == 0)

    let version = try await db.migrate(Self.migrations)
    #expect(version == 2)
    #expect(try await db.currentVersion() == 2)

    // schema_migrations tracks each applied migration by version + name.
    let rows = try await db.query(
      "SELECT version, name FROM schema_migrations ORDER BY version;")
    #expect(rows.count == 2)
    #expect(rows[0].int("version") == 1)
    #expect(rows[0].string("name") == "create_widgets")
    #expect(rows[1].int("version") == 2)

    // The migrated schema really has the added column (would throw if absent).
    let ddl = try await db.query(
      "SELECT name FROM pragma_table_info('widgets') ORDER BY name;")
    let columns = ddl.compactMap { $0.string("name") }
    #expect(columns.contains("archived"))
    #expect(columns.contains("weight"))
    await db.close()
  }

  @Test("migrate is idempotent — a second run applies nothing new")
  func migrateIsIdempotent() async throws {
    let db = try inMemory()
    #expect(try await db.migrate(Self.migrations) == 2)
    // Reapplying the same set is a no-op and does not duplicate bookkeeping rows.
    #expect(try await db.migrate(Self.migrations) == 2)
    let count = try await db.query("SELECT COUNT(*) AS c FROM schema_migrations;")
    #expect(count.first?.int("c") == 2)
    await db.close()
  }

  @Test("migrate applies only newly-added higher versions on a subsequent call")
  func migrateAppliesNewVersionsIncrementally() async throws {
    let db = try inMemory()
    #expect(try await db.migrate([Self.migrations[0]]) == 1)
    #expect(try await db.migrate(Self.migrations) == 2)
    #expect(try await db.currentVersion() == 2)
    await db.close()
  }

  @Test("a failing migration rolls back and leaves the prior version intact")
  func failingMigrationRollsBack() async throws {
    let db = try inMemory()
    let bad = [
      Self.migrations[0],
      Migration(version: 2, name: "broken", sql: "THIS IS NOT VALID SQL;"),
    ]
    await #expect(throws: DatabaseError.self) {
      _ = try await db.migrate(bad)
    }
    // Version 1 committed; the broken version 2 did not.
    #expect(try await db.currentVersion() == 1)
    await db.close()
  }

  // MARK: typed round-trip

  @Test("typed insert/select round-trips every SQLite storage class")
  func typedRoundTrip() async throws {
    let db = try inMemory()
    _ = try await db.migrate(Self.migrations)

    let insert = try await db.execute(
      "INSERT INTO widgets (name, weight, archived) VALUES (?, ?, ?);",
      [.text("gizmo"), .real(3.5), .integer(0)])
    #expect(insert.rowsAffected == 1)
    #expect(insert.lastInsertRowID == 1)

    // A NULL weight round-trips as .null.
    _ = try await db.execute(
      "INSERT INTO widgets (name, weight, archived) VALUES (?, ?, ?);",
      [.text("blank"), .null, .integer(1)])

    let rows = try await db.query(
      "SELECT id, name, weight, archived FROM widgets ORDER BY id;")
    #expect(rows.count == 2)
    #expect(rows[0].int("id") == 1)
    #expect(rows[0].string("name") == "gizmo")
    #expect(rows[0].double("weight") == 3.5)
    #expect(rows[0].bool("archived") == false)
    #expect(rows[1].string("name") == "blank")
    #expect(rows[1]["weight"] == .null)
    #expect(rows[1].bool("archived") == true)
    await db.close()
  }

  @Test("parameter binding is injection-safe")
  func parameterBindingIsSafe() async throws {
    let db = try inMemory()
    _ = try await db.migrate(Self.migrations)
    let hostile = "gizmo'); DROP TABLE widgets;--"
    _ = try await db.execute(
      "INSERT INTO widgets (name) VALUES (?);", [.text(hostile)])
    // The table still exists and stored the literal string.
    let rows = try await db.query("SELECT name FROM widgets;")
    #expect(rows.first?.string("name") == hostile)
    await db.close()
  }

  @Test("a malformed statement surfaces as DatabaseError.backend")
  func malformedStatementThrows() async throws {
    let db = try inMemory()
    await #expect(throws: DatabaseError.self) {
      _ = try await db.query("SELECT * FROM does_not_exist;")
    }
    await db.close()
  }

  @Test("blob values round-trip byte-for-byte, including empty")
  func blobRoundTrip() async throws {
    let db = try inMemory()
    _ = try await db.execute("CREATE TABLE blobs (id INTEGER PRIMARY KEY, data BLOB);")
    let payload: [UInt8] = [0x00, 0xFF, 0x10, 0x42]
    _ = try await db.execute("INSERT INTO blobs (data) VALUES (?);", [.blob(payload)])
    _ = try await db.execute("INSERT INTO blobs (data) VALUES (?);", [.blob([])])
    let rows = try await db.query("SELECT data FROM blobs ORDER BY id;")
    #expect(rows[0].blob("data") == payload)
    #expect(rows[1].blob("data") == [])
    await db.close()
  }
}
