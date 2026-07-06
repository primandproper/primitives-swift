import Foundation
import os

/// A recording ``WebSocketConnection`` test double a test drives directly — feeding it inbound messages
/// and inspecting what was sent — so ``WebSocketEventStream``'s state machine can be exercised without a
/// live socket (see ``WebSocketConnection`` for why `URLProtocol` stubbing, which works for SSE, doesn't
/// apply to WebSocket).
///
/// Promoted from the module's former private test fake per REPO-05 (every seam ships a Noop and a Mock).
/// A lock-backed `final class` rather than an `actor`: ``resume()`` / ``cancel(with:reason:)`` must stay
/// synchronous to satisfy ``WebSocketConnection``, and a lock avoids the "did the fire-and-forget Task
/// run yet" race an actor would introduce for those calls.
public final class MockWebSocketConnection: WebSocketConnection, @unchecked Sendable {
  /// How the mock answers a ``sendPing()``, letting a test drive the heartbeat's success/timeout paths.
  public enum PingResponse: Sendable {
    /// A pong comes back immediately (a live connection).
    case pong
    /// The ping itself fails (e.g. a failed handshake surfaced through the initial confirming ping).
    case failure(any Error & Sendable)
    /// No pong ever arrives — the call parks until the task is cancelled (a NAT-dropped connection). This
    /// is what the heartbeat's pong-timeout window is meant to catch.
    case hang
  }

  private struct State {
    var inbox: [Result<URLSessionWebSocketTask.Message, any Error>] = []
    var waiters: [CheckedContinuation<Void, Never>] = []
    var sentMessages: [URLSessionWebSocketTask.Message] = []
    var resumeCallCount = 0
    var cancelledWith: URLSessionWebSocketTask.CloseCode?
    var pingResponse: PingResponse = .pong
    var pingCallCount = 0
    var pingWaiters: [CheckedContinuation<Void, any Error>] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  public var resumeCallCount: Int { state.withLock { $0.resumeCallCount } }
  public var sentMessages: [URLSessionWebSocketTask.Message] { state.withLock { $0.sentMessages } }
  public var cancelledWith: URLSessionWebSocketTask.CloseCode? {
    state.withLock { $0.cancelledWith }
  }
  public var pingCallCount: Int { state.withLock { $0.pingCallCount } }

  public init() {}

  /// Sets how the next ``sendPing()`` calls respond.
  public func setPingResponse(_ response: PingResponse) {
    state.withLock { $0.pingResponse = response }
  }

  /// Queues a message (or failure) for the next ``receive()`` call to return, in FIFO order, waking any
  /// call already parked in ``receive()`` waiting for one. Continuations are resumed *after* releasing
  /// the lock, since `os_unfair_lock` isn't reentrant and a resumed waiter re-enters this same lock.
  public func enqueue(_ result: Result<URLSessionWebSocketTask.Message, any Error>) {
    let pending = state.withLock { s -> [CheckedContinuation<Void, Never>] in
      s.inbox.append(result)
      let waiters = s.waiters
      s.waiters.removeAll()
      return waiters
    }
    for waiter in pending { waiter.resume() }
  }

  public func resume() {
    state.withLock { $0.resumeCallCount += 1 }
  }

  public func send(_ message: URLSessionWebSocketTask.Message) async throws {
    state.withLock { $0.sentMessages.append(message) }
  }

  public func receive() async throws -> URLSessionWebSocketTask.Message {
    while true {
      let next: Result<URLSessionWebSocketTask.Message, any Error>? = state.withLock { s in
        s.inbox.isEmpty ? nil : s.inbox.removeFirst()
      }
      if let next {
        return try next.get()
      }
      await withCheckedContinuation { continuation in
        state.withLock { $0.waiters.append(continuation) }
      }
    }
  }

  public func sendPing() async throws {
    let response: PingResponse = state.withLock { s in
      s.pingCallCount += 1
      return s.pingResponse
    }
    switch response {
    case .pong:
      return
    case .failure(let error):
      throw error
    case .hang:
      // Park until cancelled, then surface a `CancellationError` — the shape a real hung ping takes when
      // the heartbeat's timeout task wins the race and cancels this one.
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          let resumeCancelled: Bool = state.withLock { s in
            if Task.isCancelled { return true }
            s.pingWaiters.append(continuation)
            return false
          }
          if resumeCancelled { continuation.resume(throwing: CancellationError()) }
        }
      } onCancel: {
        let waiters = state.withLock { s -> [CheckedContinuation<Void, any Error>] in
          let pending = s.pingWaiters
          s.pingWaiters.removeAll()
          return pending
        }
        for waiter in waiters { waiter.resume(throwing: CancellationError()) }
      }
    }
  }

  public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    state.withLock { $0.cancelledWith = closeCode }
  }
}
