import Foundation
import Observability
import Retry

/// An ``EventStream`` that transparently re-dials an SSE endpoint after a transport blip, following the
/// [WHATWG SSE reconnection model](https://html.spec.whatwg.org/multipage/server-sent-events.html#reconnecting).
///
/// A plain ``SSEEventStream`` finishes — permanently — the first time its byte source errors: a dropped
/// connection ends the stream for good. This wrapper instead composes the `Retry` module: it re-dials on
/// failure, sending the last-seen event id back as `Last-Event-ID` so the server can replay from where
/// the stream left off, and honoring a server-suggested `retry:` value as the reconnection delay. The
/// underlying transport blips are invisible to the consumer, whose ``events`` sequence keeps flowing.
///
/// **Retry composition.** Connect attempts are wrapped in the injected ``Retry/RetryPolicy`` (default
/// ``Retry/ExponentialBackoffPolicy``), so a run of failed dials backs off and eventually gives up per
/// the policy. A stream that connects and *then* ends — whether cleanly (server closed) or via a
/// mid-stream transport error — triggers a fresh reconnection cycle after the reconnection delay, rather
/// than surfacing as a terminal error. Only ``close()`` ends the stream for good.
///
/// **Divergence from the eager connectors.** ``SSEEventStreamConnector`` throws synchronously on a failed
/// dial; this wrapper returns immediately and surfaces a give-up (connect retries exhausted) through
/// ``events`` finishing with an error, since the whole point is to outlive individual dials.
public actor ReconnectingSSEEventStream: EventStream {
  public nonisolated let events: AsyncThrowingStream<Event, any Error>

  private let continuation: AsyncThrowingStream<Event, any Error>.Continuation
  private let connect: @Sendable ([String: String]) async throws -> SSEEventStream
  private let retryPolicy: any RetryPolicy
  private let reconnectDelay: Duration
  private let observer: any Observer
  private var loopTask: Task<Void, Never>?
  private var currentInner: SSEEventStream?
  private var closed = false

  /// - Parameters:
  ///   - retryPolicy: wraps each connect attempt; a run of failures backs off and eventually gives up.
  ///   - reconnectDelay: the delay before re-dialing after a connected stream ends, used when the server
  ///     hasn't sent a `retry:` value (which otherwise takes precedence).
  ///   - connect: opens a fresh ``SSEEventStream``, given the headers to send (the wrapper injects
  ///     `Last-Event-ID` here on resume).
  init(
    retryPolicy: any RetryPolicy,
    reconnectDelay: Duration,
    observer: any Observer,
    connect: @escaping @Sendable ([String: String]) async throws -> SSEEventStream
  ) {
    var boundContinuation: AsyncThrowingStream<Event, any Error>.Continuation!
    self.events = AsyncThrowingStream { boundContinuation = $0 }
    self.continuation = boundContinuation
    self.connect = connect
    self.retryPolicy = retryPolicy
    self.reconnectDelay = reconnectDelay
    self.observer = observer
  }

  /// Starts the reconnection loop. Split out from `init` for the same Swift-6 reason ``SSEEventStream``
  /// splits out ``SSEEventStream/start(bytes:networkTask:observer:)``.
  func start() {
    loopTask = Task { [weak self] in
      await self?.run()
    }
  }

  private func run() async {
    var headers: [String: String] = [:]

    while !closed {
      let inner: SSEEventStream
      do {
        let connect = self.connect
        let attemptHeaders = headers
        inner = try await retryPolicy.execute { try await connect(attemptHeaders) }
      } catch {
        if closed { break }
        observer.logger.error("SSE reconnect gave up after connect retries", error)
        continuation.finish(throwing: error)
        return
      }

      if closed {
        await inner.close()
        break
      }
      currentInner = inner

      do {
        for try await event in inner.events {
          continuation.yield(event)
        }
        // A clean EOF (the server closed) still reconnects — that is the SSE model.
      } catch {
        // A mid-stream transport blip must not permanently kill the stream: fall through and re-dial.
        if closed { break }
        observer.logger.info("SSE stream interrupted; reconnecting")
      }

      // Carry the resume state from the connection that just ended.
      if let id = await inner.lastSeenEventID() {
        headers["Last-Event-ID"] = id
      }
      let serverRetry = await inner.serverReconnectionTime()
      currentInner = nil

      if closed { break }

      // The server's `retry:` value, when present, is the reconnection time; otherwise the configured
      // fallback applies.
      do {
        try await Task.sleep(for: serverRetry ?? reconnectDelay)
      } catch {
        break  // cancelled via close()
      }
    }

    continuation.finish()
  }

  /// Ends reconnection for good: cancels the loop and any in-flight connection, and finishes ``events``.
  /// Idempotent.
  public func close() async {
    guard !closed else { return }
    closed = true
    loopTask?.cancel()
    await currentInner?.close()
    continuation.finish()
  }
}

/// Connects to an SSE endpoint with transparent reconnection, wrapping ``SSEEventStreamConnector`` in a
/// ``ReconnectingSSEEventStream``. Drop-in for ``EventStreamConnector`` wherever a resilient SSE consumer
/// is wanted over the fail-once ``SSEEventStreamConnector``.
public struct ReconnectingSSEEventStreamConnector: EventStreamConnector {
  private let base: SSEEventStreamConnector
  private let retryPolicy: any RetryPolicy
  private let reconnectDelay: Duration
  private let observer: any Observer

  /// - Parameters:
  ///   - session: the transport; `nil` defaults to ``StreamingSession/make()`` (streaming-safe timeouts).
  ///   - retryPolicy: wraps each connect attempt. Defaults to a plain exponential backoff.
  ///   - reconnectDelay: the delay before re-dialing after a connected stream ends and the server sent no
  ///     `retry:`.
  public init(
    session: URLSession? = nil,
    observer: any Observer,
    retryPolicy: any RetryPolicy = ExponentialBackoffPolicy(config: RetryConfig()),
    reconnectDelay: Duration = .seconds(3)
  ) {
    let session = session ?? StreamingSession.make()
    self.base = SSEEventStreamConnector(session: session, observer: observer)
    self.retryPolicy = retryPolicy
    self.reconnectDelay = reconnectDelay
    self.observer = observer
  }

  public func connect(to url: URL, headers: [String: String]) async throws -> any EventStream {
    let base = self.base
    let stream = ReconnectingSSEEventStream(
      retryPolicy: retryPolicy, reconnectDelay: reconnectDelay, observer: observer
    ) { resumeHeaders in
      // The caller's headers are the baseline; resume headers (Last-Event-ID) override on re-dial.
      try await base.openStream(to: url, headers: headers.merging(resumeHeaders) { _, new in new })
    }
    await stream.start()
    return stream
  }
}
