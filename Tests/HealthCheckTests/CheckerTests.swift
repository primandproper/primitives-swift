import Foundation
import Testing

@testable import HealthCheck

private struct Boom: Error, Equatable {}

@Suite("NoopChecker")
struct NoopCheckerTests {
  @Test("reports the configured name and never throws")
  func neverThrows() async throws {
    let checker = NoopChecker(name: "always-up")
    #expect(checker.name == "always-up")
    try await checker.check()
  }

  @Test("defaults its name to \"noop\"")
  func defaultName() {
    #expect(NoopChecker().name == "noop")
  }
}

@Suite("CheckerMock")
struct CheckerMockTests {
  @Test("an unset handler defaults to a healthy no-op check")
  func unsetHandlerIsHealthy() async throws {
    let mock = CheckerMock(name: "a")
    try await mock.check()
    let count = await mock.checkCallCount
    #expect(count == 1)
  }

  @Test("a configured handler runs and its throw propagates")
  func configuredHandlerThrows() async {
    let mock = CheckerMock(name: "a") { throw Boom() }
    await #expect(throws: Boom.self) {
      try await mock.check()
    }
  }

  @Test("check call count accumulates across calls")
  func callCountAccumulates() async throws {
    let mock = CheckerMock(name: "a")
    try await mock.check()
    try await mock.check()
    let count = await mock.checkCallCount
    #expect(count == 2)
  }
}

@Suite("ClosureChecker")
struct ClosureCheckerTests {
  @Test("a successful closure reports healthy")
  func successfulClosure() async throws {
    let checker = ClosureChecker(name: "cache") {}
    #expect(checker.name == "cache")
    try await checker.check()
  }

  @Test("a throwing closure propagates its error")
  func throwingClosure() async {
    let checker = ClosureChecker(name: "cache") { throw Boom() }
    await #expect(throws: Boom.self) {
      try await checker.check()
    }
  }
}

@Suite("DiskSpaceChecker")
struct DiskSpaceCheckerTests {
  @Test("reports healthy when available space is above the threshold")
  func aboveThresholdIsHealthy() async throws {
    let checker = DiskSpaceChecker(
      path: URL(fileURLWithPath: NSTemporaryDirectory()), minimumFreeBytes: 0)
    try await checker.check()
  }

  @Test("reports unhealthy when available space is below the threshold")
  func belowThresholdIsUnhealthy() async {
    let checker = DiskSpaceChecker(
      path: URL(fileURLWithPath: NSTemporaryDirectory()), minimumFreeBytes: .max)
    await #expect(throws: HealthCheckError.self) {
      try await checker.check()
    }
  }

  @Test("a nonexistent path is reported as unavailable")
  func nonexistentPathIsUnavailable() async {
    let checker = DiskSpaceChecker(
      path: URL(fileURLWithPath: "/no/such/path/\(UUID().uuidString)"))
    await #expect(throws: HealthCheckError.diskSpaceUnavailable) {
      try await checker.check()
    }
  }
}
