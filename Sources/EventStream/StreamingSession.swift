import Foundation

/// Builds a `URLSession` tuned for long-lived event streams (SSE / WebSocket).
///
/// `URLSessionConfiguration.default` is wrong for streaming in two ways that silently kill quiet or
/// long-running connections:
///
/// - **`timeoutIntervalForResource`** (default 7 days) caps the *total* lifetime of the transfer. An SSE
///   or WebSocket connection is meant to live indefinitely, so this factory disables it
///   (`.infinity` — the same "no ceiling on the whole transfer" stance Go's streaming clients take by
///   never setting a deadline on the request context).
/// - **`timeoutIntervalForRequest`** (default 60s) is, for a streaming body, the **inter-byte idle
///   timeout**: URLSession resets it every time new data arrives, so a stream that goes quiet for more
///   than the interval is torn down. A well-behaved SSE server sends comment "keep-alive" lines, but the
///   client can't rely on it, so this factory raises the idle window well past any reasonable keep-alive
///   cadence (see ``interByteIdleTimeout``).
///
/// This mirrors the shape of ``HTTPClientConfig/buildSessionConfiguration()`` — a small, documented
/// factory that hands back a ready `URLSessionConfiguration`/`URLSession` — without sharing its code,
/// because the timeout stance is the opposite (HTTP wants a bounded request; a stream wants an unbounded
/// one). Session injection stays possible everywhere: this is only the default the config-level factories
/// reach for when the caller doesn't supply their own.
public enum StreamingSession {
  /// Total-transfer timeout for a streaming session: disabled. Maps to
  /// `URLSessionConfiguration.timeoutIntervalForResource`.
  public static let resourceTimeout: TimeInterval = .infinity

  /// Inter-byte idle timeout: how long the connection may go without receiving a byte before URLSession
  /// tears it down. Maps to `URLSessionConfiguration.timeoutIntervalForRequest`, which — for a streaming
  /// response body — is reset on every received chunk rather than measuring the whole request. Set to one
  /// hour: far past any realistic server keep-alive cadence, but still finite so a genuinely dead
  /// connection is eventually reclaimed rather than leaking forever.
  public static let interByteIdleTimeout: TimeInterval = 3600

  /// The streaming-safe `URLSessionConfiguration`. Starts from `.default` and overrides only the two
  /// timeout knobs that matter for streaming; every other default (caches, cookies, connection reuse) is
  /// left as-is.
  public static func configuration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForResource = resourceTimeout
    configuration.timeoutIntervalForRequest = interByteIdleTimeout
    return configuration
  }

  /// A `URLSession` built from ``configuration()``.
  public static func make() -> URLSession {
    URLSession(configuration: configuration())
  }
}
