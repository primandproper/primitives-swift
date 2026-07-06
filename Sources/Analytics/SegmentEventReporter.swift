import CircuitBreaking
import Foundation
import Observability

/// A Segment-backed ``EventReporter``, ported from platform-go's `segment.EventReporter`
/// (`analytics/segment/segment.go`).
///
/// **No-vendor-SDK port.** platform-go leans on `segmentio/analytics-go`, a server-side Go SDK; per this
/// port's thin/native policy (URLSession + Codable, no SPM dependency), the batch upload the SDK does
/// internally is reimplemented directly against Segment's `POST /v1/batch` HTTP API. Segment does ship a
/// first-party Swift SDK (`analytics-swift`), but adopting a vendor SDK is out of scope here — the
/// ``EventReporter`` protocol is the seam a native/vendor adapter can wrap later.
///
/// **Auth.** Segment authenticates the batch endpoint with HTTP Basic auth: the write key as the
/// username and an empty password, exactly what the Go SDK's `req.SetBasicAuth(key, "")` produces —
/// `Authorization: Basic base64(writeKey + ":")`.
///
/// **Buffering / circuit breaker.** Identical shape to ``PostHogEventReporter``: events buffer in memory
/// and flush on ``batchSize`` or ``close()``; the ``CircuitBreaker`` gates enqueue and is driven by
/// delivery outcomes at flush time.
public actor SegmentEventReporter: EventReporter {
  /// Segment's default ingestion host. Mirrors the Go SDK's `DefaultEndpoint`.
  public static let defaultEndpoint = "https://api.segment.io"
  /// Max buffered events before an automatic flush. Mirrors the Go SDK's `DefaultBatchSize`.
  public static let defaultBatchSize = 250

  private let batchURL: URL
  private let authorization: String
  private let circuitBreaker: any CircuitBreaker
  private let session: URLSession
  private let observer: any Observer
  private let batchSize: Int

  private var buffer: [Message] = []

  /// Creates a Segment reporter.
  ///
  /// - Parameters:
  ///   - writeKey: The Segment source write key. Empty throws
  ///     ``SegmentEventReporterError/emptyWriteKey``, mirroring the Go SDK's `ErrEmptyAPIToken`.
  ///   - endpoint: The ingestion host. Empty falls back to ``defaultEndpoint``.
  ///   - circuitBreaker: Gates enqueue and is driven by delivery outcomes.
  ///   - session: Injectable so a `URLProtocol` stub can assert the emitted request in tests.
  ///   - observer: Logs flush failures on ``close()``.
  ///   - batchSize: Automatic-flush threshold.
  public init(
    writeKey: String,
    endpoint: String = "",
    circuitBreaker: any CircuitBreaker = NoopCircuitBreaker(),
    session: URLSession = .shared,
    observer: any Observer = defaultAnalyticsObserver(name: "segment_event_reporter"),
    batchSize: Int = SegmentEventReporter.defaultBatchSize
  ) throws {
    guard !writeKey.isEmpty else {
      throw SegmentEventReporterError.emptyWriteKey
    }
    let host = endpoint.isEmpty ? Self.defaultEndpoint : endpoint
    let trimmed = host.hasSuffix("/") ? String(host.dropLast()) : host
    guard let url = URL(string: "\(trimmed)/v1/batch") else {
      throw SegmentEventReporterError.invalidEndpoint(host)
    }
    self.batchURL = url
    self.authorization = "Basic " + Data("\(writeKey):".utf8).base64EncodedString()
    self.circuitBreaker = circuitBreaker
    self.session = session
    self.observer = observer
    self.batchSize = max(1, batchSize)
  }

  public func close() async {
    do {
      try await flush()
    } catch {
      observer.logger.error("flushing buffered segment events on close", error)
    }
  }

  public func addUser(userID: String, properties: [String: AnalyticsPropertyValue]) async throws {
    try await enqueue(
      Message(
        type: "identify", event: nil, userId: userID, anonymousId: nil,
        properties: nil, traits: properties, integrations: Self.enableAll))
  }

  public func eventOccurred(
    event: String, userID: String, properties: [String: AnalyticsPropertyValue]
  ) async throws {
    try await enqueue(
      Message(
        type: "track", event: event, userId: userID, anonymousId: nil,
        properties: properties, traits: nil, integrations: Self.enableAll))
  }

  public func eventOccurredAnonymous(
    event: String, anonymousID: String, properties: [String: AnalyticsPropertyValue]
  ) async throws {
    try await enqueue(
      Message(
        type: "track", event: event, userId: nil, anonymousId: anonymousID,
        properties: properties, traits: nil, integrations: Self.enableAll))
  }

  /// Delivers the buffered batch immediately, if any. Also invoked by ``close()``.
  public func flush() async throws {
    guard !buffer.isEmpty else { return }
    let messages = buffer
    buffer = []

    let request = try makeRequest(for: messages)
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
      throw SegmentEventReporterError.deliveryFailed(status: status)
    }
    await circuitBreaker.recordSuccess()
  }

  private func enqueue(_ message: Message) async throws {
    if await circuitBreaker.cannotProceed() {
      throw CircuitOpenError()
    }
    buffer.append(message)
    if buffer.count >= batchSize {
      try await flush()
    }
  }

  private func makeRequest(for messages: [Message]) throws -> URLRequest {
    var request = URLRequest(url: batchURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(authorization, forHTTPHeaderField: "Authorization")
    request.httpBody = try Self.encoder.encode(Batch(batch: messages))
    return request
  }

  /// `NewIntegrations().EnableAll()` in the Go SDK renders as `{ "all": true }`.
  private static let enableAll: [String: Bool] = ["all": true]

  /// Deterministic key ordering so tests can assert the exact emitted body.
  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  /// A single Segment batch item. A `track` message carries `event`/`properties`; an `identify`
  /// message carries `traits`. Nil optionals are omitted by the synthesized encoder.
  struct Message: Encodable, Sendable {
    let type: String
    let event: String?
    let userId: String?
    let anonymousId: String?
    let properties: [String: AnalyticsPropertyValue]?
    let traits: [String: AnalyticsPropertyValue]?
    let integrations: [String: Bool]
  }

  /// The batch envelope, matching the Go SDK's `{ "batch": [...] }`.
  struct Batch: Encodable, Sendable {
    let batch: [Message]
  }
}

/// A ``SegmentEventReporter`` failure.
public enum SegmentEventReporterError: Error, Equatable, Sendable {
  /// The write key was empty (Go's `ErrEmptyAPIToken`).
  case emptyWriteKey
  /// The configured endpoint could not form a valid batch URL.
  case invalidEndpoint(String)
  /// The batch upload returned a non-2xx status.
  case deliveryFailed(status: Int)
}
