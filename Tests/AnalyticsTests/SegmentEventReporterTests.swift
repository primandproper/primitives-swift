import CircuitBreaking
import Foundation
import Testing

@testable import Analytics

@Suite("SegmentEventReporter wire format")
struct SegmentEventReporterWireTests {
  private func makeReporter(writeKey: String = "wk_test", batchSize: Int = 250) -> (
    reporter: SegmentEventReporter, captured: AnalyticsCapturedRequest,
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
    let reporter = try! SegmentEventReporter(
      writeKey: writeKey,
      endpoint: "https://\(host)",
      session: analyticsStubbedSession(),
      batchSize: batchSize)
    return (reporter, captured, count, host)
  }

  @Test("posts to /v1/batch with Basic auth of base64(writeKey + \":\")")
  func endpointAndAuth() async throws {
    let (reporter, captured, _, host) = makeReporter(writeKey: "my-write-key")
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.eventOccurred(event: "signed_up", userID: "u1")
    await reporter.close()

    let request = try #require(captured.request)
    #expect(request.url?.absoluteString == "https://\(host)/v1/batch")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let expectedAuth = "Basic " + Data("my-write-key:".utf8).base64EncodedString()
    #expect(request.value(forHTTPHeaderField: "Authorization") == expectedAuth)
  }

  @Test("the production reporter targets the real Segment batch endpoint")
  func realEndpoint() async throws {
    // No network call is made (buffer only), but the URL is fixed to Segment's ingestion host.
    #expect(SegmentEventReporter.defaultEndpoint == "https://api.segment.io")
  }

  @Test("a track event carries type, event, userId, properties and integrations")
  func trackShape() async throws {
    let (reporter, captured, _, host) = makeReporter()
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.eventOccurred(
      event: "purchased", userID: "user-42", properties: ["amount": 9])
    await reporter.close()

    let batch = try #require(captured.json()?["batch"] as? [[String: Any]])
    let message = try #require(batch.first)
    #expect(message["type"] as? String == "track")
    #expect(message["event"] as? String == "purchased")
    #expect(message["userId"] as? String == "user-42")
    #expect(message["anonymousId"] == nil)
    let props = try #require(message["properties"] as? [String: Any])
    #expect(props["amount"] as? Double == 9)
    let integrations = try #require(message["integrations"] as? [String: Any])
    #expect(integrations["all"] as? Bool == true)
  }

  @Test("addUser emits an identify message with traits")
  func identifyShape() async throws {
    let (reporter, captured, _, host) = makeReporter()
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.addUser(userID: "user-42", properties: ["plan": "enterprise"])
    await reporter.close()

    let batch = try #require(captured.json()?["batch"] as? [[String: Any]])
    let message = try #require(batch.first)
    #expect(message["type"] as? String == "identify")
    #expect(message["userId"] as? String == "user-42")
    let traits = try #require(message["traits"] as? [String: Any])
    #expect(traits["plan"] as? String == "enterprise")
    #expect(message["event"] == nil)
  }

  @Test("an anonymous track carries anonymousId instead of userId")
  func anonymousShape() async throws {
    let (reporter, captured, _, host) = makeReporter()
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.eventOccurredAnonymous(event: "viewed", anonymousID: "anon-9")
    await reporter.close()

    let batch = try #require(captured.json()?["batch"] as? [[String: Any]])
    let message = try #require(batch.first)
    #expect(message["type"] as? String == "track")
    #expect(message["anonymousId"] as? String == "anon-9")
    #expect(message["userId"] == nil)
  }

  @Test("an empty write key throws")
  func emptyKeyThrows() {
    #expect(throws: SegmentEventReporterError.emptyWriteKey) {
      _ = try SegmentEventReporter(writeKey: "")
    }
  }
}

@Suite("SegmentEventReporter buffering and flush")
struct SegmentEventReporterBufferingTests {
  private func makeReporter(batchSize: Int = 250) -> (
    SegmentEventReporter, AnalyticsCallCounter, String
  ) {
    let host = "\(UUID().uuidString.lowercased()).test"
    let count = AnalyticsCallCounter()
    AnalyticsStubURLProtocol.register(host: host) { _ in
      count.increment()
      return .respond(status: 200)
    }
    let reporter = try! SegmentEventReporter(
      writeKey: "wk", endpoint: "https://\(host)",
      session: analyticsStubbedSession(), batchSize: batchSize)
    return (reporter, count, host)
  }

  @Test("events buffer in memory and only deliver on close")
  func buffersUntilClose() async throws {
    let (reporter, count, host) = makeReporter()
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.eventOccurred(event: "a", userID: "u")
    try await reporter.addUser(userID: "u")
    #expect(count.value == 0)

    await reporter.close()
    #expect(count.value == 1)
  }

  @Test("reaching the batch size triggers an automatic flush")
  func autoFlushAtBatchSize() async throws {
    let (reporter, count, host) = makeReporter(batchSize: 2)
    defer { AnalyticsStubURLProtocol.unregister(host) }

    try await reporter.eventOccurred(event: "a", userID: "u")
    #expect(count.value == 0)
    try await reporter.eventOccurred(event: "b", userID: "u")
    #expect(count.value == 1)
  }

  @Test("a broken circuit rejects enqueue without buffering")
  func brokenCircuitRejectsEnqueue() async throws {
    let host = "\(UUID().uuidString.lowercased()).test"
    defer { AnalyticsStubURLProtocol.unregister(host) }
    let count = AnalyticsCallCounter()
    AnalyticsStubURLProtocol.register(host: host) { _ in
      count.increment()
      return .respond(status: 200)
    }

    let reporter = try SegmentEventReporter(
      writeKey: "wk", endpoint: "https://\(host)",
      circuitBreaker: AlwaysOpenCircuitBreaker(), session: analyticsStubbedSession())

    await #expect(throws: CircuitOpenError.self) {
      try await reporter.eventOccurred(event: "a", userID: "u")
    }
    await reporter.close()
    #expect(count.value == 0)  // nothing buffered, nothing sent.
  }
}

/// A breaker that is always open, so enqueue rejects fast.
struct AlwaysOpenCircuitBreaker: CircuitBreaker {
  func recordFailure() {}
  func recordSuccess() {}
  func canProceed() -> Bool { false }
}
