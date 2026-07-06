import Foundation
import Observability

/// A live SSE ``EventStream``, backed by `URLSession.bytes(for:)`.
///
/// This is the client consumer side of platform-go's `sse` package: Go's `sseStream` is the *server's*
/// write end of the connection (`Send` writes SSE frames to an `http.ResponseWriter`); this is the
/// *client's* read end of that same connection, pumping a raw byte stream through ``SSELineSplitter``
/// and ``SSEFrameParser`` and yielding the resulting ``Event``s. Bytes are split into lines by hand
/// rather than via Foundation's `AsyncSequence.lines` — see ``SSELineSplitter``'s doc comment for why
/// that type is unusable here.
///
/// `start(bytes:networkTask:observer:)` takes the byte source as `some AsyncSequence<UInt8> & Sendable`
/// rather than the concrete `URLSession.AsyncBytes`, so tests can drive the read loop and ``close()``
/// from a fake byte source (e.g. an `AsyncStream<UInt8>` the test controls) without a network or a
/// `URLProtocol` stub.
///
/// **Cancellation.** Cancelling a `Task` suspended on byte iteration does not reliably cancel the
/// underlying `URLSessionTask` on its own, so ``close()`` also cancels the network task directly — the
/// structured-concurrency analogue of Go's `context.WithCancel` (`sse.Upgrader.UpgradeToEventStream`
/// cancels its context when the stream is closed or the client disconnects).
public actor SSEEventStream: EventStream {
  public nonisolated let events: AsyncThrowingStream<Event, any Error>

  private let continuation: AsyncThrowingStream<Event, any Error>.Continuation
  private var pumpTask: Task<Void, Never>?
  private var networkTask: URLSessionTask?

  /// The last `id:` value the parser saw on this connection, persisted per WHATWG. A reconnecting wrapper
  /// reads it after the stream ends to resume via `Last-Event-ID`.
  private var lastEventID: String?
  /// The last valid server-suggested `retry:` value, if any — the reconnection-delay floor.
  private var reconnectionTime: Duration?

  /// - Parameter bufferingPolicy: caps how many decoded events buffer for a non-draining consumer before
  ///   the overflow is dropped (see ``BoundedEventStream``). Defaults to Go's 64-slot bound.
  init(
    bufferingPolicy: AsyncThrowingStream<Event, any Error>.Continuation.BufferingPolicy =
      .bufferingOldest(EventStreamConfig.defaultBufferSize)
  ) {
    (self.events, self.continuation) = BoundedEventStream.make(bufferingPolicy: bufferingPolicy)
    self.pumpTask = nil
    self.networkTask = nil
  }

  /// Starts the background read loop. Split out from `init` because Swift 6 actor initializers cannot
  /// store a `Task` that captures `self` (the compiler treats the capture as "escaping" mid-init); the
  /// connector calls this immediately after construction, once `self` is a fully-initialized actor
  /// reference. `networkTask` is optional so a test can drive a fake byte source with nothing to cancel.
  func start<Bytes: AsyncSequence & Sendable>(
    bytes: Bytes, networkTask: URLSessionTask?, observer: any Observer
  ) where Bytes.Element == UInt8 {
    self.networkTask = networkTask
    // Tear down the network task and read loop if the consumer abandons `events` (e.g. breaks out of
    // its `for try await` without calling `close()`, or its consuming task is cancelled). Without this
    // the pump keeps iterating bytes and the `URLSessionTask` stays live forever. The handler is
    // `@Sendable` and non-isolated, so it hops back onto the actor via an unstructured `Task`.
    continuation.onTermination = { [weak self] _ in
      Task { await self?.close() }
    }
    pumpTask = Task { [weak self] in
      await self?.pump(bytes: bytes, observer: observer)
    }
  }

  /// The last-seen event id on this connection, for a reconnecting wrapper to resume with. Actor-isolated,
  /// so read it only after the stream's ``events`` has finished.
  func lastSeenEventID() -> String? { lastEventID }

  /// The server-suggested reconnection delay (`retry:`) seen on this connection, if any.
  func serverReconnectionTime() -> Duration? { reconnectionTime }

  private func pump<Bytes: AsyncSequence & Sendable>(bytes: Bytes, observer: any Observer) async
  where Bytes.Element == UInt8 {
    var splitter = SSELineSplitter()
    var parser = SSEFrameParser()
    do {
      for try await byte in bytes {
        if let line = splitter.consume(byte) {
          let event = parser.consume(line)
          lastEventID = parser.lastEventID
          reconnectionTime = parser.reconnectionTime
          if let event { continuation.yield(event) }
        }
      }
      if let line = splitter.flush() {
        let event = parser.consume(line)
        lastEventID = parser.lastEventID
        reconnectionTime = parser.reconnectionTime
        if let event { continuation.yield(event) }
      }
      continuation.finish()
    } catch {
      if Task.isCancelled {
        continuation.finish()
      } else {
        observer.logger.error("SSE stream read failed", error)
        continuation.finish(throwing: error)
      }
    }
  }

  /// Cancels the underlying network task and read loop, and finishes ``events``. Idempotent: a second
  /// call is a no-op because cancelling an already-cancelled task, and finishing an already-finished
  /// stream, are both no-ops.
  public func close() async {
    networkTask?.cancel()
    pumpTask?.cancel()
    continuation.finish()
  }
}

/// Connects to an SSE endpoint, the client analogue of platform-go's `sse.NewUpgrader`.
public struct SSEEventStreamConnector: EventStreamConnector {
  private let session: URLSession
  private let observer: any Observer
  private let bufferSize: Int

  public init(
    session: URLSession,
    observer: any Observer,
    bufferSize: Int = EventStreamConfig.defaultBufferSize
  ) {
    self.session = session
    self.observer = observer
    self.bufferSize = bufferSize
  }

  /// Opens `url` as an SSE connection. Mirrors the shape of Go's `UpgradeToEventStream`: a non-2xx
  /// response, a non-HTTP response, a response whose `Content-Type` isn't `text/event-stream`, or any
  /// transport failure throws before any ``SSEEventStream`` is created, since there is nothing yet to
  /// hand back.
  ///
  /// `headers` are applied verbatim to the outbound request; a reconnecting wrapper uses this to send
  /// `Last-Event-ID` on resume.
  public func connect(to url: URL, headers: [String: String]) async throws -> any EventStream {
    try await openStream(to: url, headers: headers)
  }

  /// The concrete-typed variant of ``connect(to:headers:)``, returning ``SSEEventStream`` so a
  /// reconnecting wrapper can read its ``SSEEventStream/lastSeenEventID()``/
  /// ``SSEEventStream/serverReconnectionTime()`` after the stream ends.
  func openStream(to url: URL, headers: [String: String] = [:]) async throws -> SSEEventStream {
    try await observer.operation(name: "SSE connect") { op in
      var request = URLRequest(url: url)
      // Apply caller headers first, then set `Accept` last so a custom header can't clobber the SSE
      // content-type negotiation the stream depends on.
      for (name, value) in headers {
        request.setValue(value, forHTTPHeaderField: name)
      }
      request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

      op.set(Keys.connectionURL, url.absoluteString)
      let (bytes, response) = try await session.bytes(for: request)

      guard let http = response as? HTTPURLResponse else {
        op.acknowledge(EventStreamError.nonHTTPResponse, "connecting to SSE stream")
        throw EventStreamError.nonHTTPResponse
      }
      guard (200..<300).contains(http.statusCode) else {
        let error = EventStreamError.connectionFailed(status: http.statusCode)
        op.acknowledge(error, "connecting to SSE stream")
        throw error
      }
      // A 200 with the wrong MIME type (e.g. an HTML error page) must fail the connection rather than be
      // parsed as an event stream and observed as silence, per the WHATWG processing model.
      let contentType = http.value(forHTTPHeaderField: "Content-Type")
      guard Self.isEventStream(contentType) else {
        let error = EventStreamError.invalidContentType(received: contentType)
        op.acknowledge(error, "connecting to SSE stream")
        throw error
      }
      op.set(Keys.responseStatus, http.statusCode)

      let stream = SSEEventStream(bufferingPolicy: .bufferingOldest(bufferSize))
      await stream.start(bytes: bytes, networkTask: bytes.task, observer: observer)
      return stream
    }
  }

  /// Whether a `Content-Type` header names the `text/event-stream` MIME type, ignoring any parameters
  /// (`; charset=utf-8`) and case, per the SSE spec's essence-only comparison.
  private static func isEventStream(_ contentType: String?) -> Bool {
    guard let essence = contentType?.split(separator: ";").first else { return false }
    return essence.trimmingCharacters(in: .whitespaces).lowercased() == "text/event-stream"
  }
}
