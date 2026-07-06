import CircuitBreaking
import Foundation
import Observability

/// A PostHog-backed ``EventReporter``, ported from platform-go's `posthog.EventReporter`
/// (`analytics/posthog/posthog.go`).
///
/// **No-vendor-SDK port.** platform-go leans on `posthog/posthog-go`, a server-side Go SDK; per this
/// port's thin/native policy (URLSession + Codable, no SPM dependency), the batch upload the SDK does
/// internally is reimplemented directly against PostHog's `POST {endpoint}/batch` HTTP API. PostHog does
/// ship a first-party Swift SDK, but adopting a vendor SDK is out of scope here — the ``EventReporter``
/// protocol is the seam a native/vendor adapter can wrap later.
///
/// **Buffering.** Like the Go SDK (which enqueues into a channel and flushes on a timer/batch-size/close),
/// events are buffered in memory and delivered as a single batch. This port flushes when the buffer
/// reaches ``batchSize`` or when ``close()`` is called, rather than on a wall-clock timer — a background
/// ticker is more machinery than a thin client needs.
///
/// **Circuit breaker.** The injected ``CircuitBreaker`` gates *enqueue* (a broken circuit rejects fast
/// with ``CircuitOpenError`` before buffering, mirroring Go's `CannotProceed()` check) and is driven by
/// *delivery* outcomes at flush time (`recordSuccess()`/`recordFailure()`), mirroring how Go drove the
/// breaker from the SDK's asynchronous delivery callback rather than from the enqueue itself.
public actor PostHogEventReporter: EventReporter {
  /// PostHog US Cloud, the default when ``PostHogConfig/endpoint`` is empty. Mirrors the Go SDK's
  /// `DefaultEndpoint`.
  public static let defaultEndpoint = "https://app.posthog.com"
  /// Max buffered events before an automatic flush. Mirrors the Go SDK's `DefaultBatchSize`.
  public static let defaultBatchSize = 250

  private let apiKey: String
  private let batchURL: URL
  private let circuitBreaker: any CircuitBreaker
  private let session: URLSession
  private let observer: any Observer
  private let batchSize: Int

  private var buffer: [Event] = []

  /// Creates a PostHog reporter.
  ///
  /// - Parameters:
  ///   - apiKey: The PostHog project API key. Empty throws ``PostHogEventReporterError/emptyAPIKey``,
  ///     mirroring the Go SDK's `ErrEmptyAPIToken`.
  ///   - endpoint: The ingestion host. Empty falls back to ``defaultEndpoint`` (US Cloud).
  ///   - circuitBreaker: Gates enqueue and is driven by delivery outcomes.
  ///   - session: Injectable so a `URLProtocol` stub can assert the emitted request in tests.
  ///   - observer: Logs flush failures on ``close()``.
  ///   - batchSize: Automatic-flush threshold.
  public init(
    apiKey: String,
    endpoint: String = "",
    circuitBreaker: any CircuitBreaker = NoopCircuitBreaker(),
    session: URLSession = .shared,
    observer: any Observer = defaultAnalyticsObserver(name: "posthog_event_reporter"),
    batchSize: Int = PostHogEventReporter.defaultBatchSize
  ) throws {
    guard !apiKey.isEmpty else {
      throw PostHogEventReporterError.emptyAPIKey
    }
    let host = endpoint.isEmpty ? Self.defaultEndpoint : endpoint
    let trimmed = host.hasSuffix("/") ? String(host.dropLast()) : host
    guard let url = URL(string: "\(trimmed)/batch") else {
      throw PostHogEventReporterError.invalidEndpoint(host)
    }
    self.apiKey = apiKey
    self.batchURL = url
    self.circuitBreaker = circuitBreaker
    self.session = session
    self.observer = observer
    self.batchSize = max(1, batchSize)
  }

  public func close() async {
    do {
      try await flush()
    } catch {
      observer.logger.error("flushing buffered posthog events on close", error)
    }
  }

  public func addUser(userID: String, properties: [String: AnalyticsPropertyValue]) async throws {
    // Identify semantics: event "$identify", traits carried in "$set".
    try await enqueue(Event(event: "$identify", distinctId: userID, properties: nil, set: properties))
  }

  public func eventOccurred(
    event: String, userID: String, properties: [String: AnalyticsPropertyValue]
  ) async throws {
    try await enqueue(Event(event: event, distinctId: userID, properties: properties, set: nil))
  }

  public func eventOccurredAnonymous(
    event: String, anonymousID: String, properties: [String: AnalyticsPropertyValue]
  ) async throws {
    // PostHog has no separate anonymous channel; the anonymous id is the distinct id, exactly as Go's
    // reporter enqueues a Capture with DistinctId = anonymousID.
    try await enqueue(Event(event: event, distinctId: anonymousID, properties: properties, set: nil))
  }

  /// Delivers the buffered batch immediately, if any. Also invoked by ``close()``.
  public func flush() async throws {
    guard !buffer.isEmpty else { return }
    let events = buffer
    buffer = []

    let request = try makeRequest(for: events)
    let response: URLResponse
    do {
      (_, response) = try await session.data(for: request)
    } catch {
      await circuitBreaker.recordFailure()
      throw error
    }

    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      await circuitBreaker.recordFailure()
      let status = (response as? HTTPURLResponse)?.statusCode ?? -1
      throw PostHogEventReporterError.deliveryFailed(status: status)
    }
    await circuitBreaker.recordSuccess()
  }

  private func enqueue(_ event: Event) async throws {
    if await circuitBreaker.cannotProceed() {
      throw CircuitOpenError()
    }
    buffer.append(event)
    if buffer.count >= batchSize {
      try await flush()
    }
  }

  private func makeRequest(for events: [Event]) throws -> URLRequest {
    var request = URLRequest(url: batchURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try Self.encoder.encode(Batch(apiKey: apiKey, batch: events))
    return request
  }

  /// Deterministic key ordering so tests can assert the exact emitted body.
  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  /// A single PostHog batch item. A capture event carries `properties`; an identify event carries
  /// `$set`. Nil optionals are omitted by the synthesized encoder, so a capture never emits `$set` and
  /// an identify never emits `properties`.
  struct Event: Encodable, Sendable {
    let event: String
    let distinctId: String
    let properties: [String: AnalyticsPropertyValue]?
    let set: [String: AnalyticsPropertyValue]?

    enum CodingKeys: String, CodingKey {
      case event
      case distinctId = "distinct_id"
      case properties
      case set = "$set"
    }
  }

  /// The batch envelope, matching the Go SDK's `{ "api_key": ..., "batch": [...] }`.
  struct Batch: Encodable, Sendable {
    let apiKey: String
    let batch: [Event]

    enum CodingKeys: String, CodingKey {
      case apiKey = "api_key"
      case batch
    }
  }
}

/// A ``PostHogEventReporter`` failure.
public enum PostHogEventReporterError: Error, Equatable, Sendable {
  /// The API key was empty (Go's `ErrEmptyAPIToken`).
  case emptyAPIKey
  /// The configured endpoint could not form a valid batch URL.
  case invalidEndpoint(String)
  /// The batch upload returned a non-2xx status.
  case deliveryFailed(status: Int)
}
