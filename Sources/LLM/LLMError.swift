import Foundation

/// Errors surfaced by the LLM providers.
///
/// platform-go leans on any-llm's typed sentinel family (`ErrAuthentication`, `ErrRateLimit` with a
/// `RetryAfter`, `ErrModelNotFound`, `ErrInvalidRequest`, `ErrContextLength`, `ErrProvider`, …) and the
/// platform layer passes those through unchanged. Because this port makes the HTTP call itself rather than
/// delegating to any-llm, it reproduces the *classification* directly from each provider's response —
/// mapping HTTP status (and, for 429, the `Retry-After` header) onto the equivalent cases. The contract a
/// caller relies on is preserved: **a 429 comes back as ``rateLimit(retryAfter:)`` and is never retried
/// internally** (compose `Retry` around ``LLMProvider/completion(_:)`` for backoff), matching the explicit
/// "this method does not retry" note on Go's `Completion`.
public enum LLMError: Error, Equatable, Sendable {
  /// The provider config is missing its API key. The analogue of any-llm's `ErrMissingAPIKey`.
  case missingAPIKey
  /// The config failed validation. Carries the human-readable reason.
  case invalidConfig(String)
  /// Authentication failed (HTTP 401/403). any-llm's `ErrAuthentication`.
  case authentication
  /// The provider rate-limited the request (HTTP 429). Carries the `Retry-After` delay in seconds when the
  /// provider supplied one, mirroring any-llm's `RateLimitError.RetryAfter`. Not retried here by design.
  case rateLimit(retryAfter: TimeInterval?)
  /// The requested model does not exist (HTTP 404, or a 400 the provider attributes to the model).
  /// any-llm's `ErrModelNotFound`. Carries the model id.
  case modelNotFound(String)
  /// The request was rejected as invalid (HTTP 400). any-llm's `ErrInvalidRequest` / `ErrContextLength`.
  /// Carries the provider's message.
  case invalidRequest(String)
  /// A non-2xx status not covered by a more specific case. any-llm's `ErrProvider`. Carries status + body
  /// message.
  case provider(status: Int, message: String)
  /// A 2xx response whose body couldn't be decoded into the expected shape. Carries a short reason.
  case malformedResponse(String)

  public var description: String {
    switch self {
    case .missingAPIKey: return "missing API key"
    case .invalidConfig(let reason): return "invalid llm config: \(reason)"
    case .authentication: return "llm authentication failed"
    case .rateLimit(let retryAfter):
      if let retryAfter { return "llm rate limited; retry after \(retryAfter)s" }
      return "llm rate limited"
    case .modelNotFound(let model): return "llm model not found: \(model)"
    case .invalidRequest(let message): return "invalid llm request: \(message)"
    case .provider(let status, let message): return "llm provider error (\(status)): \(message)"
    case .malformedResponse(let reason): return "malformed llm response: \(reason)"
    }
  }
}

extension LLMError: LocalizedError {
  public var errorDescription: String? { description }
}

extension LLMError {
  /// Classifies a non-2xx HTTP response into the matching case, reproducing any-llm's status→sentinel
  /// mapping. `message` is the best human-readable string the caller could pull from the error body;
  /// `model` is the request's resolved model id (used to name a `.modelNotFound`).
  static func classify(
    status: Int, message: String, model: String, retryAfterHeader: String?
  ) -> LLMError {
    switch status {
    case 401, 403:
      return .authentication
    case 404:
      return .modelNotFound(model)
    case 429:
      return .rateLimit(retryAfter: parseRetryAfter(retryAfterHeader))
    case 400:
      // any-llm splits 400 into ErrModelNotFound / ErrContextLength / ErrInvalidRequest by inspecting the
      // provider's error `code`/`type`; without that structured field we route on the message text and
      // otherwise fall through to the general invalid-request case.
      let lowered = message.lowercased()
      if lowered.contains("model") && (lowered.contains("not found") || lowered.contains("does not exist"))
      {
        return .modelNotFound(model)
      }
      return .invalidRequest(message)
    default:
      return .provider(status: status, message: message)
    }
  }

  /// Parses a `Retry-After` header into a delay in seconds, honoring **both** RFC 7231 forms — a
  /// *delta-seconds* integer (`Retry-After: 30`) and an *HTTP-date* (`Retry-After: Wed, 21 Oct 2015
  /// 07:28:00 GMT`), the latter measured from `now`. Previously only the numeric form was handled, so a
  /// date-form header silently dropped the hint; this closes that gap to match ``HTTPClient``'s parser.
  /// Returns `nil` when the header is absent or unparseable; a past date or non-positive count yields `0`.
  static func parseRetryAfter(_ header: String?, now: Date = Date()) -> TimeInterval? {
    guard let raw = header?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }

    if let seconds = TimeInterval(raw) {
      return max(0, seconds)
    }
    if let date = httpDateFormatter.date(from: raw) {
      return max(0, date.timeIntervalSince(now))
    }
    return nil
  }

  /// RFC 7231 IMF-fixdate formatter (`en_US_POSIX`, GMT), mirroring ``HTTPClient``'s. Held as a shared
  /// `static let` rather than rebuilt on every rate-limited response.
  private static let httpDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter
  }()
}
