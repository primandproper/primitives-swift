import Testing

@testable import Retry

private actor Counter {
  private(set) var value = 0
  func increment() { value += 1 }
}

private struct Boom: Error {}

@Suite("MockRetryPolicy")
struct MockRetryPolicyTests {
  @Test("default runs the operation once and records the call")
  func passThrough() async throws {
    let policy = MockRetryPolicy()
    let result = try await policy.execute { 7 }

    #expect(result == 7)
    #expect(await policy.executeCallCount == 1)
    #expect(await policy.attemptCount == 1)
  }

  @Test("re-runs up to the configured attempt count on repeated failure")
  func retriesOnThrow() async {
    let policy = MockRetryPolicy(attempts: 3)
    let counter = Counter()

    await #expect(throws: Boom.self) {
      try await policy.execute {
        await counter.increment()
        throw Boom()
      }
    }

    #expect(await counter.value == 3)
    #expect(await policy.attemptCount == 3)
    #expect(await policy.executeCallCount == 1)
  }

  @Test("stops attempting once the operation succeeds")
  func stopsOnSuccess() async throws {
    let policy = MockRetryPolicy(attempts: 5)
    let counter = Counter()

    let result = try await policy.execute { () async throws -> Int in
      await counter.increment()
      if await counter.value < 2 { throw Boom() }
      return 99
    }

    #expect(result == 99)
    #expect(await counter.value == 2)
    #expect(await policy.attemptCount == 2)
  }
}
