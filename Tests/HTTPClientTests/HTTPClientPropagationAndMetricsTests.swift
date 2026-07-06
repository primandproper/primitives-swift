import CircuitBreaking
import Foundation
import Observability
import Testing
import os

@testable import HTTPClient

// MARK: - NET-23: W3C trace-context propagation

@Suite("HTTPClient trace propagation")
struct HTTPClientPropagationTests {
  @Test("the outbound request carries a traceparent matching the operation's span context")
  func injectsTraceparent() async throws {
    let token = UUID().uuidString
    // The stub records the header the transport actually saw, proving injection reached the wire.
    let seen = OSAllocatedUnfairLock<String?>(initialState: nil)
    StubURLProtocol.register(token) { request in
      seen.withLock { $0 = request.value(forHTTPHeaderField: W3CPropagation.traceparentHeader) }
      return .respond(status: 200, body: Data(), headers: [:])
    }
    defer { StubURLProtocol.unregister(token) }

    let observer = recordingObserver("test")
    let client = HTTPClient(
      session: stubbedSession(), observer: observer, metrics: NoopMetricsProvider())

    _ = try await client.perform(stubbedRequest(token: token))

    // The known span context comes from the recording observer's single operation.
    let context = try #require(observer.operations.first?.span.context)
    let traceparent = try #require(seen.withLock { $0 })
    #expect(traceparent == W3CPropagation.traceparent(for: context))

    // And it round-trips back to the same identity via the extractor.
    let extracted = try #require(W3CPropagation.extract(traceparent: traceparent))
    #expect(extracted.traceID == context.traceID)
    #expect(extracted.spanID == context.spanID)
  }
}

// MARK: - NET-26: failure-path metrics

@Suite("HTTPClient failure metrics")
struct HTTPClientFailureMetricsTests {
  private func requestCounters(_ metrics: RecordingMetricsProvider)
    -> [RecordingMetricsProvider.CounterEvent]
  {
    metrics.counterEvents(named: "http.client.requests")
  }

  @Test("a completed round-trip increments the requests counter tagged outcome=success")
  func successIsTaggedSuccess() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .respond(status: 200, body: Data(), headers: [:]) }
    defer { StubURLProtocol.unregister(token) }

    let metrics = RecordingMetricsProvider()
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"), metrics: metrics)

    _ = try await client.perform(stubbedRequest(token: token))

    let events = requestCounters(metrics)
    #expect(events.count == 1)
    #expect(events.first?.tags["outcome"] == "success")
    #expect(events.first?.tags["method"] == "GET")
    #expect(events.first?.tags["status"] == "200")
  }

  @Test("a transport timeout increments the requests counter tagged outcome=error, error=timeout")
  func transportTimeoutIsCounted() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .fail(URLError(.timedOut)) }
    defer { StubURLProtocol.unregister(token) }

    let metrics = RecordingMetricsProvider()
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"), metrics: metrics)

    await #expect(throws: (any Error).self) {
      _ = try await client.perform(stubbedRequest(token: token))
    }

    let events = requestCounters(metrics)
    // The failure path must move the counter — otherwise a timeout storm is invisible.
    #expect(events.count == 1)
    let tags = try #require(events.first?.tags)
    #expect(tags["outcome"] == "error")
    #expect(tags["error"] == "timeout")
    #expect(tags["method"] == "GET")
    // No successful round-trip, so no status is tagged.
    #expect(tags["status"] == nil)
  }

  @Test("a non-timeout transport fault is tagged error=connection")
  func connectionFaultIsCounted() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .fail(URLError(.notConnectedToInternet)) }
    defer { StubURLProtocol.unregister(token) }

    let metrics = RecordingMetricsProvider()
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"), metrics: metrics)

    await #expect(throws: (any Error).self) {
      _ = try await client.perform(stubbedRequest(token: token))
    }

    let tags = try #require(requestCounters(metrics).first?.tags)
    #expect(tags["outcome"] == "error")
    #expect(tags["error"] == "connection")
  }

  @Test("an unclassified transport fault falls back to the error=transport bucket")
  func unclassifiedTransportFaultIsCounted() async throws {
    let token = UUID().uuidString
    // Neither a timeout nor one of errorReason's connection codes, so it lands in the default `transport`
    // bucket — the branch the timeout/connection cases above don't reach.
    StubURLProtocol.register(token) { _ in .fail(URLError(.badServerResponse)) }
    defer { StubURLProtocol.unregister(token) }

    let metrics = RecordingMetricsProvider()
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"), metrics: metrics)

    await #expect(throws: (any Error).self) {
      _ = try await client.perform(stubbedRequest(token: token))
    }

    let events = requestCounters(metrics)
    #expect(events.count == 1)
    let tags = try #require(events.first?.tags)
    #expect(tags["outcome"] == "error")
    #expect(tags["error"] == "transport")
    #expect(tags["method"] == "GET")
    #expect(tags["status"] == nil)
  }

  @Test("an open breaker increments the requests counter tagged outcome=circuit_broken")
  func circuitBrokenIsCounted() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .respond(status: 200, body: Data(), headers: [:]) }
    defer { StubURLProtocol.unregister(token) }

    let metrics = RecordingMetricsProvider()
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"), metrics: metrics,
      circuitBreaker: HTTPClientCircuitBreakerTests.TestBreaker(open: true))

    await #expect(throws: HTTPClientError.circuitBroken) {
      _ = try await client.perform(stubbedRequest(token: token))
    }

    let events = requestCounters(metrics)
    #expect(events.count == 1)
    #expect(events.first?.tags["outcome"] == "circuit_broken")
    #expect(events.first?.tags["method"] == "GET")
  }

  @Test("a cancellation is tagged outcome=cancelled, not error, so it doesn't inflate the error rate")
  func cancellationIsTaggedDistinctly() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .blockUntilCancelled }
    defer { StubURLProtocol.unregister(token) }

    let metrics = RecordingMetricsProvider()
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"), metrics: metrics)

    let task = Task { try await client.perform(stubbedRequest(token: token)) }
    // Give the request time to reach the parked stub before cancelling.
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    await #expect(throws: (any Error).self) { _ = try await task.value }

    let events = requestCounters(metrics)
    #expect(events.count == 1)
    #expect(events.first?.tags["outcome"] == "cancelled")
    // A user-initiated cancel must NOT be counted as an error.
    #expect(events.first?.tags["error"] == nil)
  }
}
