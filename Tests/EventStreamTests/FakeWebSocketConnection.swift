import Foundation
import os

@testable import EventStream

/// A fake ``WebSocketConnection`` a test drives directly, feeding it inbound messages and inspecting
/// what ``WebSocketEventStream`` sent — the seam that lets ``WebSocketEventStream``'s state machine be
/// unit-tested without a live socket (see ``WebSocketConnection``'s doc comment for why `URLProtocol`
/// stubbing, which works for SSE, doesn't apply to WebSocket).
///
/// A lock-backed class rather than an actor, matching `HTTPClientTests`' `AttemptCounter`/`TestBreaker`:
/// ``resume()``/``cancel(with:reason:)`` must stay synchronous to satisfy ``WebSocketConnection``, and a
/// lock avoids the "did the fire-and-forget Task run yet" race an actor would introduce for those calls.
final class FakeWebSocketConnection: WebSocketConnection, @unchecked Sendable {
  private struct State {
    var inbox: [Result<URLSessionWebSocketTask.Message, any Error>] = []
    var waiters: [CheckedContinuation<Void, Never>] = []
    var sentMessages: [URLSessionWebSocketTask.Message] = []
    var resumeCallCount = 0
    var cancelledWith: URLSessionWebSocketTask.CloseCode?
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  var resumeCallCount: Int { state.withLock { $0.resumeCallCount } }
  var sentMessages: [URLSessionWebSocketTask.Message] { state.withLock { $0.sentMessages } }
  var cancelledWith: URLSessionWebSocketTask.CloseCode? { state.withLock { $0.cancelledWith } }

  /// Queues a message (or failure) for the next ``receive()`` call to return, in FIFO order, waking any
  /// call already parked in ``receive()`` waiting for one. Continuations are resumed *after* releasing
  /// the lock, since `os_unfair_lock` isn't reentrant and a resumed waiter re-enters this same lock.
  func enqueue(_ result: Result<URLSessionWebSocketTask.Message, any Error>) {
    let pending = state.withLock { s -> [CheckedContinuation<Void, Never>] in
      s.inbox.append(result)
      let waiters = s.waiters
      s.waiters.removeAll()
      return waiters
    }
    for waiter in pending { waiter.resume() }
  }

  func resume() {
    state.withLock { $0.resumeCallCount += 1 }
  }

  func send(_ message: URLSessionWebSocketTask.Message) async throws {
    state.withLock { $0.sentMessages.append(message) }
  }

  func receive() async throws -> URLSessionWebSocketTask.Message {
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

  func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    state.withLock { $0.cancelledWith = closeCode }
  }
}
