import Testing

@testable import Database

@Suite("MockDatabase")
struct MockDatabaseTests {
  @Test("records calls and returns quiet defaults when no handler is set")
  func recordsAndDefaults() async throws {
    let mock = MockDatabase()

    let result = try await mock.execute("INSERT INTO t VALUES (?);", [.integer(7)])
    #expect(result == ExecResult(rowsAffected: 0, lastInsertRowID: 0))
    #expect(try await mock.query("SELECT 1;").isEmpty)
    #expect(try await mock.migrate([]) == 0)
    #expect(try await mock.currentVersion() == 0)
    await mock.close()

    let executeCalls = await mock.executeCalls
    #expect(executeCalls.count == 1)
    #expect(
      executeCalls.first
        == MockDatabase.Call(sql: "INSERT INTO t VALUES (?);", parameters: [.integer(7)]))
    #expect(await mock.queryCalls.count == 1)
    #expect(await mock.migrateCalls.count == 1)
    #expect(await mock.currentVersionCallCount == 1)
    #expect(await mock.closeCallCount == 1)
  }

  @Test("installed handlers drive the return values")
  func handlersDriveReturns() async throws {
    let mock = MockDatabase(
      executeHandler: { _, _ in ExecResult(rowsAffected: 3, lastInsertRowID: 42) },
      queryHandler: { _, _ in [Row(columns: ["id"], values: [.integer(1)])] },
      migrateHandler: { migrations in migrations.count }
    )

    #expect(try await mock.execute("x").lastInsertRowID == 42)
    let rows = try await mock.query("y")
    #expect(rows.first?.int("id") == 1)
    let applied = try await mock.migrate([
      Migration(version: 1, sql: "a"), Migration(version: 2, sql: "b"),
    ])
    #expect(applied == 2)
  }
}
