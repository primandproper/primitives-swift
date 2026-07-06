/// An error that carries a lower bound on how long the retry loop should wait before its next attempt —
/// the retry-side analogue of an HTTP `Retry-After` header.
///
/// When ``ExponentialBackoffPolicy`` catches an error conforming to this, it raises the next backoff
/// delay to at least ``retryAfterFloor``: the floor wins only when it exceeds the computed (and possibly
/// jittered) backoff, so a smaller or `nil` floor leaves the normal exponential schedule untouched. The
/// floor is honored verbatim and is deliberately *not* clamped to ``RetryConfig/maxDelay`` — a server's
/// explicit "wait this long" directive should be obeyed rather than shortened.
///
/// This is the clean seam HTTP-status retries build on: a client converts a `429`/`503` into an error
/// carrying the parsed `Retry-After` delay, and this protocol lets the policy honor that server hint
/// without the `Retry` module knowing anything about HTTP. It mirrors nothing in platform-go's `retry`
/// package directly — Go's callers layer `Retry-After` handling on top — but keeping it in the policy
/// gives the port a single, testable place for the floor.
public protocol RetryDelayFloor: Error {
  /// A minimum delay to impose before the next retry, or `nil` to impose no floor.
  var retryAfterFloor: Duration? { get }
}
