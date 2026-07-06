import Foundation
import Testing

@testable import Analytics

@Suite("PostHogEventReporter wire format")
struct PostHogEventReporterWireTests {
  /// A reporter pointed at a unique stub host, with a captured-request box wired up.
  private func makeReporter(batchSize: Int = 250) -> (
    reporter: PostHogEventReporter, captured: AnalyticsCapturedRequest,
    count: AnalyticsCallCounter, host: String
  ) {
    let host = "\(UUID().uuidString.lowercased()).test"
    let captured = AnalyticsCapturedRequest()
    let count = AnalyticsCallCounter()
    AnalyticsStubURLProtocol.register(host: host) { request in
      count.increment()
      captured.set(request)
      return .respond(status: 200)
    }
    let reporter = try! PostHogEventReporter(
      apiKey: "phc_test_key",
      endpoint: "https://\(host)",
      session: analyticsStubbedSession(),
      batchSize: batchSize)
    return (reporter, captured, count, host)
  }

  @Test("posts to {endpoint}/batch with a JSON content type and api_key envelope")
  func endpointAndEnvelope() async throws {
    let (reporter, captured, _, host) = makeReporter()
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.eventOccurred(event: "signed_up", userID: "u1", properties: ["plan": "pro"])
    await reporter.close()

    let request = try #require(captured.request)
    #expect(request.url?.absoluteString == "https://\(host)/batch")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let json = try #require(captured.json())
    #expect(json["api_key"] as? String == "phc_test_key")
    let batch = try #require(json["batch"] as? [[String: Any]])
    #expect(batch.count == 1)
  }

  @Test("a capture event carries event, distinct_id and properties")
  func captureShape() async throws {
    let (reporter, captured, _, host) = makeReporter()
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.eventOccurred(event: "purchased", userID: "user-42", properties: ["amount": 9])
    await reporter.close()

    let batch = try #require(captured.json()?["batch"] as? [[String: Any]])
    let event = try #require(batch.first)
    #expect(event["event"] as? String == "purchased")
    #expect(event["distinct_id"] as? String == "user-42")
    let props = try #require(event["properties"] as? [String: Any])
    #expect(props["amount"] as? Double == 9)
    // A capture never carries $set.
    #expect(event["$set"] == nil)
  }

  @Test("addUser emits an $identify event with traits under $set")
  func identifyShape() async throws {
    let (reporter, captured, _, host) = makeReporter()
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.addUser(userID: "user-42", properties: ["plan": "enterprise"])
    await reporter.close()

    let batch = try #require(captured.json()?["batch"] as? [[String: Any]])
    let event = try #require(batch.first)
    #expect(event["event"] as? String == "$identify")
    #expect(event["distinct_id"] as? String == "user-42")
    let set = try #require(event["$set"] as? [String: Any])
    #expect(set["plan"] as? String == "enterprise")
    // An identify never carries a top-level properties bag.
    #expect(event["properties"] == nil)
  }

  @Test("an anonymous event uses the anonymous id as the distinct id")
  func anonymousShape() async throws {
    let (reporter, captured, _, host) = makeReporter()
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.eventOccurredAnonymous(event: "viewed", anonymousID: "anon-9")
    await reporter.close()

    let batch = try #require(captured.json()?["batch"] as? [[String: Any]])
    let event = try #require(batch.first)
    #expect(event["event"] as? String == "viewed")
    #expect(event["distinct_id"] as? String == "anon-9")
  }

  @Test("an empty endpoint defaults to PostHog US Cloud")
  func defaultEndpoint() async throws {
    let reporter = try PostHogEventReporter(apiKey: "phc_key")
    _ = reporter  // constructed without throwing; URL built from the default host.
    #expect(PostHogEventReporter.defaultEndpoint == "https://app.posthog.com")
  }

  @Test("an empty api key throws")
  func emptyKeyThrows() {
    #expect(throws: PostHogEventReporterError.emptyAPIKey) {
      _ = try PostHogEventReporter(apiKey: "")
    }
  }
}

@Suite("PostHogEventReporter buffering and flush")
struct PostHogEventReporterBufferingTests {
  private func makeReporter(batchSize: Int = 250) -> (
    PostHogEventReporter, AnalyticsCallCounter, String
  ) {
    let host = "\(UUID().uuidString.lowercased()).test"
    let count = AnalyticsCallCounter()
    AnalyticsStubURLProtocol.register(host: host) { _ in
      count.increment()
      return .respond(status: 200)
    }
    let reporter = try! PostHogEventReporter(
      apiKey: "phc_key", endpoint: "https://\(host)",
      session: analyticsStubbedSession(), batchSize: batchSize)
    return (reporter, count, host)
  }

  @Test("events buffer in memory and only deliver on close")
  func buffersUntilClose() async throws {
    let (reporter, count, host) = makeReporter()
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.eventOccurred(event: "a", userID: "u")
    try await reporter.eventOccurred(event: "b", userID: "u")
    #expect(count.value == 0)  // nothing sent yet — purely buffered.

    await reporter.close()
    #expect(count.value == 1)  // one batch, both events.
  }

  @Test("reaching the batch size triggers an automatic flush")
  func autoFlushAtBatchSize() async throws {
    let (reporter, count, host) = makeReporter(batchSize: 2)
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.eventOccurred(event: "a", userID: "u")
    #expect(count.value == 0)
    try await reporter.eventOccurred(event: "b", userID: "u")
    #expect(count.value == 1)  // second event hit the threshold and flushed.
  }

  @Test("closing an empty reporter makes no request")
  func closeEmptyMakesNoRequest() async throws {
    let (reporter, count, host) = makeReporter()
    defer { AnalyticsStubURLProtocol.unregister(host) }

    await reporter.close()
    #expect(count.value == 0)
  }

  @Test("a non-2xx delivery trips the circuit breaker and throws on flush")
  func deliveryFailureRecordsFailure() async throws {
    let host = "\(UUID().uuidString.lowercased()).test"
    defer { AnalyticsStubURLProtocol.unregister(host) }
    AnalyticsStubURLProtocol.register(host: host) { _ in .respond(status: 500) }

    let reporter = try PostHogEventReporter(
      apiKey: "phc_key", endpoint: "https://\(host)", session: analyticsStubbedSession())
    try await reporter.eventOccurred(event: "a", userID: "u")

    await #expect(throws: PostHogEventReporterError.self) {
      try await reporter.flush()
    }
  }
}
