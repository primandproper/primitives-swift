import CircuitBreaking
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
  /// A breaker whose gate and recorded calls the test can inspect. Conforms to the unified async
  /// ``CircuitBreaking/CircuitBreaker`` protocol (NET-10); its synchronous, lock-guarded method bodies
  /// still satisfy the protocol's `async` requirements.
  final class TestBreaker: CircuitBreaker, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (open: false, failed: 0, succeeded: 0))
    init(open: Bool) { state.withLock { $0.open = open } }
    func recordFailure() { state.withLock { $0.failed += 1 } }
    func recordSuccess() { state.withLock { $0.succeeded += 1 } }
    func canProceed() -> Bool { state.withLock { !$0.open } }
    var failures: Int { state.withLock { $0.failed } }
    var successes: Int { state.withLock { $0.succeeded } }
  }

  /// A breaker that starts closed and trips permanently open the moment it records its first failure —
  /// used to prove the gate is re-checked on *every* retry attempt (NET-10), not just once before the
  /// retry loop.
  final class TripAfterFirstFailureBreaker: CircuitBreaker, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (open: false, failed: 0))
    func recordFailure() { state.withLock { $0.failed += 1; $0.open = true } }
    func recordSuccess() {}
    func canProceed() -> Bool { state.withLock { !$0.open } }
    var failures: Int { state.withLock { $0.failed } }
  }

  // NET-10: the breaker gate moved from a once-per-`perform` check to a per-attempt check inside the
  // retried closure. A breaker that trips on the first attempt's failure must fail the remaining retry
  // attempts fast — at the gate, without hitting the transport again.
  @Test("the breaker gate is re-checked per retry attempt, short-circuiting once it trips mid-retry")
  func gateRecheckedPerRetryAttempt() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      attempts.increment()
      return .fail(URLError(.timedOut))
    }
    defer { StubURLProtocol.unregister(token) }

    let breaker = TripAfterFirstFailureBreaker()
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), retryPolicy: fastRetryPolicy(maxAttempts: 3),
      circuitBreaker: breaker)

    await #expect(throws: HTTPClientError.circuitBroken) {
      _ = try await client.perform(stubbedRequest(token: token))
    }

    // Only the first attempt reached the network; once the breaker tripped, attempts 2 and 3 were
    // rejected at the gate and the retry loop surfaced the circuitBroken sentinel.
    #expect(attempts.value == 1)
    #expect(breaker.failures == 1)
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

  // NET-24: a cancellation landing during the retry backoff must surface the last attempt's error, not a
  // bare CancellationError — the HTTPClient-level counterpart of the Retry unit test. The first attempt
  // fails with a distinctive transport error; a long backoff guarantees the cancel lands during it.
  @Test("cancelling mid-retry surfaces the last attempt's error, not a bare CancellationError")
  func cancellationSurfacesLastError() async throws {
    let token = UUID().uuidString
    StubURLProtocol.register(token) { _ in .fail(URLError(.timedOut)) }
    defer { StubURLProtocol.unregister(token) }

    let policy = ExponentialBackoffPolicy(
      config: RetryConfig(maxAttempts: 5, initialDelay: .seconds(3600), useJitter: false))
    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), retryPolicy: policy)

    let task = Task { try await client.perform(stubbedRequest(token: token)) }
    // Let the first attempt fail and the loop enter its (very long) backoff, then cancel.
    try await Task.sleep(for: .milliseconds(150))
    task.cancel()

    var thrown: (any Error)?
    do { _ = try await task.value } catch { thrown = error }
    let error = try #require(thrown)
    // The surfaced error is the wrapped transport failure, not a bare CancellationError.
    #expect(!(error is CancellationError))
  }
}

@Suite("HTTPClient retryable-status retries")
struct HTTPClientRetryableStatusTests {
  @Test("a retryable 503 is retried until it succeeds")
  func retriesRetryableStatusUntilSuccess() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      let n = attempts.increment()
      if n < 3 { return .respond(status: 503, body: Data("busy".utf8), headers: [:]) }
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

  @Test("a retryable 429 is retried and, once attempts are exhausted, the response is returned")
  func exhaustsRetryableStatusReturnsResponse() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      attempts.increment()
      return .respond(status: 429, body: Data("slow down".utf8), headers: [:])
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), retryPolicy: fastRetryPolicy(maxAttempts: 3))

    // Exhausting the retries hands back the 429 verbatim rather than throwing (Go's Client.Do contract).
    let response = try await client.perform(stubbedRequest(token: token))

    #expect(response.statusCode == 429)
    #expect(response.body == Data("slow down".utf8))
    #expect(attempts.value == 3)
  }

  @Test("a non-retryable status (e.g. 500) is returned on the first attempt, unretried")
  func nonRetryableStatusNotRetried() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      attempts.increment()
      return .respond(status: 500, body: Data(), headers: [:])
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), retryPolicy: fastRetryPolicy(maxAttempts: 3))

    let response = try await client.perform(stubbedRequest(token: token))

    #expect(response.statusCode == 500)
    #expect(attempts.value == 1)
  }

  @Test("a custom classifier can widen the retryable set")
  func customClassifierWidensRetryableSet() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      let n = attempts.increment()
      if n < 2 { return .respond(status: 502, body: Data(), headers: [:]) }
      return .respond(status: 200, body: Data(), headers: [:])
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), retryPolicy: fastRetryPolicy(maxAttempts: 3),
      retryableStatus: { $0 == 502 })

    let response = try await client.perform(stubbedRequest(token: token))

    #expect(response.statusCode == 200)
    #expect(attempts.value == 2)
  }
}

@Suite("HTTPClient idempotency gating")
struct HTTPClientIdempotencyTests {
  private func request(method: String, token: String) -> URLRequest {
    var request = stubbedRequest(token: token)
    request.httpMethod = method
    return request
  }

  @Test("a non-idempotent POST is not retried by default")
  func nonIdempotentNotRetriedByDefault() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      attempts.increment()
      return .respond(status: 503, body: Data(), headers: [:])
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), retryPolicy: fastRetryPolicy(maxAttempts: 3))

    let response = try await client.perform(request(method: "POST", token: token))

    // Not retried: a single attempt, and the 503 comes back as a plain response.
    #expect(response.statusCode == 503)
    #expect(attempts.value == 1)
  }

  @Test("a non-idempotent POST is retried when the caller opts in")
  func nonIdempotentRetriedWhenOptedIn() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      let n = attempts.increment()
      if n < 3 { return .respond(status: 503, body: Data(), headers: [:]) }
      return .respond(status: 200, body: Data(), headers: [:])
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), retryPolicy: fastRetryPolicy(maxAttempts: 3))

    let response = try await client.perform(
      request(method: "POST", token: token), retryNonIdempotent: true)

    #expect(response.statusCode == 200)
    #expect(attempts.value == 3)
  }

  @Test("an idempotent PUT is retried by default")
  func idempotentPutRetriedByDefault() async throws {
    let token = UUID().uuidString
    let attempts = AttemptCounter()
    StubURLProtocol.register(token) { _ in
      let n = attempts.increment()
      if n < 2 { return .respond(status: 503, body: Data(), headers: [:]) }
      return .respond(status: 200, body: Data(), headers: [:])
    }
    defer { StubURLProtocol.unregister(token) }

    let client = HTTPClient(
      session: stubbedSession(), observer: recordingObserver("test"),
      metrics: NoopMetricsProvider(), retryPolicy: fastRetryPolicy(maxAttempts: 3))

    let response = try await client.perform(request(method: "PUT", token: token))

    #expect(response.statusCode == 200)
    #expect(attempts.value == 2)
  }
}

@Suite("HTTPClient Retry-After floor parsing")
struct HTTPClientRetryAfterTests {
  private func response(retryAfter: String?) -> HTTPURLResponse {
    var headers: [String: String] = [:]
    if let retryAfter { headers["Retry-After"] = retryAfter }
    return HTTPURLResponse(
      url: URL(string: "https://example.test")!, statusCode: 503, httpVersion: "HTTP/1.1",
      headerFields: headers)!
  }

  @Test("numeric delta-seconds parse to that many seconds")
  func numericFloor() {
    #expect(HTTPClient.retryAfterFloor(from: response(retryAfter: "120")) == .seconds(120))
  }

  @Test("an HTTP-date parses to the remaining time from now")
  func httpDateFloor() {
    // A fixed IMF-fixdate and a `now` 60s before it → a 60s floor.
    let target = "Wed, 21 Oct 2015 07:29:00 GMT"
    let now = Date(timeIntervalSince1970: 1_445_412_480)  // 2015-10-21 07:28:00 GMT
    let floor = HTTPClient.retryAfterFloor(from: response(retryAfter: target), now: now)
    #expect(floor == .seconds(60))
  }

  @Test("a past HTTP-date floors at zero (retry immediately)")
  func pastDateFloorsAtZero() {
    let past = "Wed, 21 Oct 2015 07:28:00 GMT"
    let now = Date(timeIntervalSince1970: 1_445_412_600)  // 2 minutes later
    #expect(HTTPClient.retryAfterFloor(from: response(retryAfter: past), now: now) == .zero)
  }

  @Test("an absent or unparseable header imposes no floor")
  func absentOrGarbageIsNil() {
    #expect(HTTPClient.retryAfterFloor(from: response(retryAfter: nil)) == nil)
    #expect(HTTPClient.retryAfterFloor(from: response(retryAfter: "not-a-date")) == nil)
  }
}
