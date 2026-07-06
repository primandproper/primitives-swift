import Foundation
import Retry

/// The status-classification seam: which HTTP status codes ``HTTPClient`` should treat as *retryable*
/// (as opposed to a settled non-2xx result to hand back). Kept as a `@Sendable` closure so it is a clean
/// injection point — a caller can widen it (e.g. also retry `502`/`504`) and later items build richer
/// classification on top of the same shape rather than a hard-coded switch.
public typealias RetryableStatusClassifier = @Sendable (Int) -> Bool

extension HTTPClient {
  /// Default classifier: retry `429 Too Many Requests` and `503 Service Unavailable` — the two statuses
  /// that carry a standardized `Retry-After` and denote a *transient* server condition a later attempt
  /// can plausibly clear. Everything else (including other 5xx) is returned to the caller unretried,
  /// preserving Go's `Client.Do` "a non-2xx is a result" contract for statuses we can't safely replay.
  public static let defaultRetryableStatus: RetryableStatusClassifier = { status in
    status == 429 || status == 503
  }

  /// HTTP methods whose semantics are idempotent per RFC 7231 §4.2.2, so replaying them on a transient
  /// failure is safe. Retries default to this set; a non-idempotent method (`POST`, `PATCH`, `CONNECT`)
  /// is retried only when the caller opts in — see ``perform(_:retryNonIdempotent:)``.
  static let idempotentMethods: Set<String> = ["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]

  /// Whether `method` is idempotent (case-insensitively) and therefore safe to retry by default.
  static func isIdempotent(_ method: String) -> Bool {
    idempotentMethods.contains(method.uppercased())
  }

  /// Parses a `Retry-After` header into a delay floor, honoring **both** RFC 7231 forms:
  /// - *delta-seconds*: a non-negative integer count of seconds (`Retry-After: 120`).
  /// - *HTTP-date*: an IMF-fixdate (`Retry-After: Wed, 21 Oct 2015 07:28:00 GMT`), whose floor is the
  ///   remaining time from `now`.
  ///
  /// Returns `nil` when the header is absent or unparseable (impose no floor); a past date or `0` seconds
  /// yields `.zero` (retry immediately, but still a valid floor). `now` is injectable so the HTTP-date
  /// branch is deterministically testable. This closes the same numeric-only gap noted in `LLMHTTP`.
  static func retryAfterFloor(from response: HTTPURLResponse, now: Date = Date()) -> Duration? {
    guard
      let raw = response.value(forHTTPHeaderField: "Retry-After")?
        .trimmingCharacters(in: .whitespaces), !raw.isEmpty
    else {
      return nil
    }

    // delta-seconds form.
    if let seconds = Int(raw) {
      return seconds > 0 ? .seconds(seconds) : .zero
    }

    // HTTP-date (IMF-fixdate) form.
    if let date = httpDateFormatter.date(from: raw) {
      let interval = date.timeIntervalSince(now)
      return interval > 0 ? .seconds(interval) : .zero
    }

    return nil
  }

  /// Formatter for the RFC 7231 IMF-fixdate (`EEE, dd MMM yyyy HH:mm:ss zzz`, always GMT). `en_US_POSIX`
  /// pins month/day names so a non-US device locale can't break parsing. Held as a shared `static let`
  /// rather than rebuilt on every rate-limited response.
  private static let httpDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter
  }()
}

/// A retryable HTTP status (e.g. `429`/`503`) reified as an error so it can flow through the
/// ``Retry/RetryPolicy`` loop instead of returning early as a settled response.
///
/// It carries the completed ``HTTPResponse`` so that once retries are exhausted the client can hand the
/// response back to the caller verbatim — preserving Go's `Client.Do` contract that a non-2xx is a
/// *result*, not a thrown error. Its ``retryAfterFloor`` conformance feeds the server's `Retry-After`
/// hint into the backoff schedule. It never escapes ``HTTPClient`` (the top-level `perform` unwraps it),
/// so it stays `internal`.
struct RetryableStatusError: Error, RetryDelayFloor {
  let response: HTTPResponse
  let retryAfterFloor: Duration?
}
