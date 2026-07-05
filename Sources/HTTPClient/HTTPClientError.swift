import Foundation

/// Errors surfaced by ``HTTPClient``, ported from the failure modes of platform-go's `httpclient`
/// (plus the `circuitbreaking.ErrCircuitBroken` sentinel it composes with).
///
/// **Non-2xx is deliberately not here.** Go's `*http.Client.Do` returns the response for a 4xx/5xx
/// without an error — a non-success status is a *result*, not a transport failure. ``HTTPClient``
/// keeps that contract: it hands back an ``HTTPResponse`` (with ``HTTPResponse/isSuccess`` `false`)
/// rather than throwing, so status handling stays with the caller. Only genuine transport/protocol
/// failures and a tripped breaker throw.
public enum HTTPClientError: Error, Equatable, CustomStringConvertible {
  /// The circuit breaker was open, so the request was refused without hitting the network. The Swift
  /// analogue of Go's `circuitbreaking.ErrCircuitBroken`.
  case circuitBroken
  /// A response came back but wasn't an `HTTPURLResponse` (e.g. a non-HTTP URL scheme), so there is
  /// no status code to reason about. Go never sees this because its transport is HTTP-only.
  case nonHTTPResponse
  /// The config failed validation. Carries the human-readable reason.
  case invalidConfig(String)

  public var description: String {
    switch self {
    case .circuitBroken:
      return "service circuit broken"
    case .nonHTTPResponse:
      return "response was not an HTTP response"
    case .invalidConfig(let reason):
      return "invalid http client config: \(reason)"
    }
  }
}
