import Foundation

/// The outcome of a completed request, ported from the parts of Go's `*http.Response` a client
/// actually consumes.
///
/// Go hands back a live `*http.Response` whose `Body` is a stream the caller must drain and close.
/// `URLSession`'s async API has already buffered the body into `Data` by the time it returns, so this
/// mirrors that: the body is eagerly present and there is nothing to close. Keeping the shape to
/// `Sendable` value types (`Int`/`[String: String]`/`Data`) — rather than storing the reference-typed,
/// non-`Sendable` `HTTPURLResponse` — lets an ``HTTPResponse`` cross concurrency domains freely.
public struct HTTPResponse: Sendable, Equatable {
  /// The HTTP status code (e.g. `200`, `404`).
  public let statusCode: Int
  /// Response headers, flattened to strings. Header names preserve the casing `URLSession` reports.
  public let headers: [String: String]
  /// The fully-buffered response body.
  public let body: Data

  public init(statusCode: Int, headers: [String: String], body: Data) {
    self.statusCode = statusCode
    self.headers = headers
    self.body = body
  }

  /// Whether the status is in the 2xx range. The convenience Go callers write inline as
  /// `resp.StatusCode >= 200 && resp.StatusCode < 300`.
  public var isSuccess: Bool { (200..<300).contains(statusCode) }

  /// Builds the value view from a `URLSession` result. `allHeaderFields` is `[AnyHashable: Any]`;
  /// non-string keys/values are rendered with `String(describing:)` so the map is always well-typed.
  init(http: HTTPURLResponse, body: Data) {
    var headers: [String: String] = [:]
    for (key, value) in http.allHeaderFields {
      let keyString = key as? String ?? String(describing: key)
      headers[keyString] = value as? String ?? String(describing: value)
    }
    self.init(statusCode: http.statusCode, headers: headers, body: body)
  }
}
