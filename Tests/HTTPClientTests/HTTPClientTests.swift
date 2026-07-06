import Foundation
import Observability
import Retry
import Testing
import os

@testable import HTTPClient

// A fast policy so retry tests don't sleep for real time.
private func fastRetryPolicy(maxAttempts: UInt = 3) -> ExponentialBackoffPolicy {
  ExponentialBackoffPolicy(
    config: RetryConfig(
      maxAttempts: maxAttempts,
      initialDelay: .milliseconds(1),
      maxDelay: .milliseconds(5),
      multiplier: 2,
      useJitter: false))
}

@Suite("HTTPClient requests")
struct HTTPClientRequestTests {
  @Test("a successful request returns the body and status")
  func successReturnsBodyAndStatus() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in
      .respond(status: 200, body: Data("hello".utf8), headers: ["Content-Type": "text/plain"])
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider())

    let response = try await client.perform(stubbedRequest(token: token))

    #expect(response.statusCode == 200)
    #expect(response.isSuccess)
    #expect(response.body == Data("hello".utf8))
    #expect(response.headers["Content-Type"] == "text/plain")
  }

  @Test("a non-2xx status returns the response without throwing, matching Go's Client.Do")
  func nonSuccessReturnsResponse() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in
      .respond(status: 404, body: Data("nope".utf8), headers: [:])
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider())

    let response = try await client.perform(stubbedRequest(token: token))

    #expect(response.statusCode == 404)
    #expect(!response.isSuccess)
    #expect(response.body == Data("nope".utf8))
  }

  @Test("the observer records a span with request/response attributes and ends it")
  func observerSpanIsInvoked() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .respond(status: 201, body: Data(), headers: [:]) }
    defer { StubURLProtocol.unregister(token) }

    let observer = recordingObserver("test")
    let client = HTTPClient(
      session: stubbedSession(), observer: observer, metrics: NoopMetricsProvider())

    _ = try await client.perform(stubbedRequest(token: token))

    let ops = observer.operations
    #expect(ops.count == 1)
    let op = try #require(ops.first)
    #expect(op.name.hasPrefix("HTTP GET"))
    #expect(op.value(forKey: Keys.requestMethod) == "GET")
    #expect(op.value(forKey: Keys.responseStatus) == "201")
    #expect(op.ended)
    #expect(op.recordedErrors.isEmpty)
  }
}

@Suite("HTTPClient retry composition")
struct HTTPClientRetryTests {
  @Test("retries a transport failure until it succeeds")
  func retriesUntilSuccess() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      let n = attempts.increment()
      // Fail the first two attempts, succeed on the third.
      if n < 3 { return .fail(URLError(.timedOut)) }
      return .respond(status: 200, body: Data("ok".utf8), headers: [:])
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), retryPolicy: fastRetryPolicy(maxAttempts: 3))

    let response = try await client.perform(stubbedRequest(token: token))

    #expect(response.statusCode == 200)
    #expect(attempts.value == 3)
  }

  @Test("propagates the error when all attempts fail")
  func exhaustsAndThrows() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      attempts.increment()
      return .fail(URLError(.cannotConnectToHost))
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), retryPolicy: fastRetryPolicy(maxAttempts: 2))

    await #expect(throws: (any Error).self) {
      _ = try await client.perform(stubbedRequest(token: token))
    }
    #expect(attempts.value == 2)
  }

  @Test("without a policy a transport failure throws on the first attempt")
  func noRetryThrowsImmediately() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      attempts.increment()
      return .fail(URLError(.notConnectedToInternet))
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider())

    await #expect(throws: (any Error).self) {
      _ = try await client.perform(stubbedRequest(token: token))
    }
    #expect(attempts.value == 1)
  }
}

@Suite("HTTPClient circuit breaking")
struct HTTPClientCircuitBreakerTests {
  /// A breaker whose gate and recorded calls the test can inspect.
  final class TestBreaker: CircuitBreaker, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (open: false, failed: 0, succeeded: 0))
    init(open: Bool) { state.withLock { $0.open = open } }
    func failed() { state.withLock { $0.failed += 1 } }
    func succeeded() { state.withLock { $0.succeeded += 1 } }
    func canProceed() -> Bool { state.withLock { !$0.open } }
    var failures: Int { state.withLock { $0.failed } }
    var successes: Int { state.withLock { $0.succeeded } }
  }

  @Test("an open breaker fails fast with circuitBroken and never hits the transport")
  func openBreakerFailsFast() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      attempts.increment()
      return .respond(status: 200, body: Data(), headers: [:])
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), circuitBreaker: TestBreaker(open: true))

    await #expect(throws: HTTPClientError.circuitBroken) {
      _ = try await client.perform(stubbedRequest(token: token))
    }
    #expect(attempts.value == 0)
  }

  @Test("a closed breaker records success on a completed request")
  func closedBreakerRecordsSuccess() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .respond(status: 200, body: Data(), headers: [:]) }
    defer { StubURLProtocol.unregister(token) }

    let breaker = TestBreaker(open: false)
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), circuitBreaker: breaker)

    _ = try await client.perform(stubbedRequest(token: token))

    #expect(breaker.successes == 1)
    #expect(breaker.failures == 0)
  }

  @Test("a closed breaker records failure on a transport error")
  func closedBreakerRecordsFailure() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .fail(URLError(.timedOut)) }
    defer { StubURLProtocol.unregister(token) }

    let breaker = TestBreaker(open: false)
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), circuitBreaker: breaker)

    await #expect(throws: (any Error).self) {
      _ = try await client.perform(stubbedRequest(token: token))
    }
    #expect(breaker.failures == 1)
    #expect(breaker.successes == 0)
  }

  // NET-03: a completed round-trip with a gateway-fault status (502/503/504) must record a breaker
  // *failure*, not success — otherwise a 100%-500s server can never trip the breaker. The response is
  // still returned (matching Go's Client.Do); only the breaker outcome differs.
  @Test("the default classifier records failure for 502/503/504 while still returning the response")
  func closedBreakerRecordsFailureOnGatewayStatus() async throws {
    for status in [502, 503, 504] {
      let token = UUID().uuidString
      StubURLProtocol.register(token) { _ in .respond(status: status, body: Data(), headers: [:]) }
      defer { StubURLProtocol.unregister(token) }

      let breaker = TestBreaker(open: false)
      let client = HTTPClient(
        session: stubbedSession(), observer: recordingObserver("test"),
        metrics: NoopMetricsProvider(), circuitBreaker: breaker)

      let response = try await client.perform(stubbedRequest(token: token))

      #expect(response.statusCode == status)
      #expect(breaker.failures == 1)
      #expect(breaker.successes == 0)
    }
  }

  @Test("the default classifier records success for a 500 (only the gateway trio counts as failure)")
  func closedBreakerRecordsSuccessOnPlain500() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .respond(status: 500, body: Data(), headers: [:]) }
    defer { StubURLProtocol.unregister(token) }

    let breaker = TestBreaker(open: false)
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), circuitBreaker: breaker)

    _ = try await client.perform(stubbedRequest(token: token))

    #expect(breaker.successes == 1)
    #expect(breaker.failures == 0)
  }

  @Test("an injected status classifier overrides the default failure policy")
  func injectedClassifierOverridesDefault() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .respond(status: 429, body: Data(), headers: [:]) }
    defer { StubURLProtocol.unregister(token) }

    let breaker = TestBreaker(open: false)
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), circuitBreaker: breaker,
      statusFailureClassifier: { $0 == 429 })

    _ = try await client.perform(stubbedRequest(token: token))

    #expect(breaker.failures == 1)
    #expect(breaker.successes == 0)
  }
}

@Suite("HTTPClient cancellation")
struct HTTPClientCancellationTests {
  @Test("cancelling the surrounding task unwinds the request by throwing")
  func cancellationPropagates() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .blockUntilCancelled }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider())

    let task = Task {
      try await client.perform(stubbedRequest(token: token))
    }

    // Give the request a moment to start blocking, then cancel it.
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()

    await #expect(throws: (any Error).self) {
      _ = try await task.value
    }
  }

  // NET-02: a cancelled request is the caller abandoning the work, not a transport fault, so it must
  // NOT record a breaker failure — otherwise a burst of user cancellations could trip a healthy
  // breaker. Reuses the circuit-breaker suite's inspectable breaker.
  @Test("cancelling a request does not record a breaker failure")
  func cancellationDoesNotCountAsBreakerFailure() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .blockUntilCancelled }
    defer { StubURLProtocol.unregister(token) }

    let breaker = HTTPClientCircuitBreakerTests.TestBreaker(open: false)
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), circuitBreaker: breaker)

    let task = Task {
      try await client.perform(stubbedRequest(token: token))
    }

    try await Task.sleep(for: .milliseconds(50))
    task.cancel()

    await #expect(throws: (any Error).self) {
      _ = try await task.value
    }
    #expect(breaker.failures == 0)
    #expect(breaker.successes == 0)
  }
}
