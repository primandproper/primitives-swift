import os
import Testing

@testable import Analytics

/// A thread-safe flag, since a `Sendable` closure can't mutate a plain captured `var`. Mirrors
/// `HTTPClientTests`' `AttemptCounter`.
private final class Flag: @unchecked Sendable {
  private let state = OSAllocatedUnfairLock(initialState: false)
  func set() { state.withLock { $0 = true } }
  var isSet: Bool { state.withLock { $0 } }
}

@Suite("EventReporterMock")
struct EventReporterMockTests {
  @Test("records close calls and invokes the handler")
  func close() async {
    let invoked = Flag()
    let mock = EventReporterMock(closeHandler: { invoked.set() })

    await mock.close()

    #expect(invoked.isSet)
    #expect(await mock.closeCallCount == 1)
  }

  @Test("close with no handler is a no-op")
  func closeWithoutHandler() async {
    let mock = EventReporterMock()
    await mock.close()
    #expect(await mock.closeCallCount == 1)
  }

  @Test("records addUser calls with the exact arguments")
  func addUser() async throws {
    let mock = EventReporterMock()

    try await mock.addUser(userID: "user123", properties: ["plan": "pro"])

    let calls = await mock.addUserCalls
    #expect(calls == [EventReporterMock.AddUserCall(userID: "user123", properties: ["plan": "pro"])])
  }

  @Test("propagates an error thrown by the addUser handler")
  func addUserThrows() async {
    struct Boom: Error, Equatable {}
    let mock = EventReporterMock(addUserHandler: { _, _ in throw Boom() })

    await #expect(throws: Boom.self) {
      try await mock.addUser(userID: "user123", properties: [:])
    }

    // The call is recorded even though the handler failed.
    let calls = await mock.addUserCalls
    #expect(calls.count == 1)
  }

  @Test("records eventOccurred calls with the exact arguments")
  func eventOccurred() async throws {
    let mock = EventReporterMock()

    try await mock.eventOccurred(event: "signed_up", userID: "user123", properties: ["source": "web"])

    let calls = await mock.eventOccurredCalls
    #expect(
      calls == [
        EventReporterMock.EventOccurredCall(
          event: "signed_up", userID: "user123", properties: ["source": "web"])
      ])
  }

  @Test("records eventOccurredAnonymous calls with the exact arguments")
  func eventOccurredAnonymous() async throws {
    let mock = EventReporterMock()

    try await mock.eventOccurredAnonymous(
      event: "viewed_page", anonymousID: "anon123", properties: ["path": "/home"])

    let calls = await mock.eventOccurredAnonymousCalls
    #expect(
      calls == [
        EventReporterMock.EventOccurredAnonymousCall(
          event: "viewed_page", anonymousID: "anon123", properties: ["path": "/home"])
      ])
  }

  @Test("conforms to EventReporter for use behind the protocol")
  func conformsToProtocol() async throws {
    let mock = EventReporterMock()
    let reporter: any EventReporter = mock

    try await reporter.eventOccurred(event: "e", userID: "u", properties: [:])

    let calls = await mock.eventOccurredCalls
    #expect(calls.count == 1)
  }
}
