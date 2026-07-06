import Testing

@testable import Database

@Suite("NoopDatabase")
struct NoopDatabaseTests {
  @Test("every operation is a benign no-op")
  func operationsAreNoops() async throws {
    let db = NoopDatabase()
    #expect(try await db.migrate([Migration(version: 1, sql: "CREATE TABLE t (id INTEGER);")]) == 0)
    #expect(try await db.currentVersion() == 0)

    let result = try await db.execute("INSERT INTO t VALUES (1);")
    #expect(result.rowsAffected == 0)
    #expect(result.lastInsertRowID == 0)

    #expect(try await db.query("SELECT * FROM t;").isEmpty)
    #expect(try await db.queryOne("SELECT * FROM t;") == nil)
    await db.close()
  }
}
