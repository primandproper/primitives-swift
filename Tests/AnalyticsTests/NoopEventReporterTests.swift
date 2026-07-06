import Testing

@testable import Analytics

@Suite("NoopEventReporter")
struct NoopEventReporterTests {
  // Held as `any EventReporter` (not the concrete struct) so each call goes through the
  // async-throwing protocol requirement, matching how a real app would inject this reporter.
  private var reporter: any EventReporter { NoopEventReporter() }

  @Test("close does not throw or crash")
  func close() async {
    await reporter.close()
  }

  @Test("addUser returns without throwing")
  func addUser() async throws {
    try await reporter.addUser(userID: "user123", properties: ["key": "value"])
  }

  @Test("eventOccurred returns without throwing")
  func eventOccurred() async throws {
    try await reporter.eventOccurred(
      event: "event_name", userID: "user123", properties: ["key": "value"])
  }

  @Test("eventOccurredAnonymous returns without throwing")
  func eventOccurredAnonymous() async throws {
    try await reporter.eventOccurredAnonymous(
      event: "event_name", anonymousID: "anon123", properties: ["key": "value"])
  }

  @Test("the properties-less convenience overloads forward to the full methods")
  func convenienceOverloads() async throws {
    try await reporter.addUser(userID: "user123")
    try await reporter.eventOccurred(event: "event_name", userID: "user123")
    try await reporter.eventOccurredAnonymous(event: "event_name", anonymousID: "anon123")
  }
}
