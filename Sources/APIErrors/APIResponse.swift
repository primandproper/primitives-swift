import Filtering

/// Per-response context the API attaches to every payload, ported from platform-go's
/// `errors/http.ResponseDetails`. `traceID` ties a client-observed failure back to the server-side
/// trace — correlate it with the observability span IDs.
public struct ResponseDetails: Codable, Sendable, Equatable {
  public var currentAccountID: String
  public var traceID: String

  public init(currentAccountID: String = "", traceID: String = "") {
    self.currentAccountID = currentAccountID
    self.traceID = traceID
  }
}

/// The error body of an API response, ported from platform-go's `errors/http.APIError`. It is itself a
/// Swift `Error`, so networking code can `throw` it directly; ``description`` matches Go's
/// `"CODE: message"` rendering. Following the repo's `ObservabilityError` idiom, it's a
/// `struct: Error, CustomStringConvertible` rather than a `LocalizedError` or error enum.
public struct APIError: Error, Codable, Sendable, Equatable, CustomStringConvertible {
  public let message: String
  public let code: ErrorCode

  public init(message: String, code: ErrorCode) {
    self.message = message
    self.code = code
  }

  public var description: String { "\(code.rawValue): \(message)" }
}

/// The generic JSON envelope the API returns, ported from platform-go's `errors/http.APIResponse[T]`:
/// an optional `data` payload, optional `pagination`, optional `error`, and always-present `details`.
/// Unlike ``QueryFilteredResult``, pagination here is **nested** under `"pagination"`.
public struct APIResponse<T: Codable & Sendable>: Codable, Sendable {
  public var data: T?
  public var pagination: Pagination?
  public var error: APIError?
  public var details: ResponseDetails

  public init(
    data: T? = nil,
    pagination: Pagination? = nil,
    error: APIError? = nil,
    details: ResponseDetails = ResponseDetails()
  ) {
    self.data = data
    self.pagination = pagination
    self.error = error
    self.details = details
  }

  /// Unwraps the response: throws ``error`` if present, otherwise returns ``data``. The client-side
  /// analogue of Go's `APIError.AsError()` ergonomics. Throws a synthetic ``APIError`` when neither a
  /// payload nor an error is present (a malformed success response).
  public func get() throws -> T {
    if let error { throw error }
    guard let data else {
      throw APIError(message: "response contained no data", code: .nothingSpecific)
    }
    return data
  }
}

/// Placeholder payload for responses that carry no `data` — e.g. error-only responses or endpoints
/// returning just a status. Mirrors Go's use of `APIResponse[any]` for error responses.
public struct EmptyData: Codable, Sendable, Equatable {
  public init() {}
}

/// Convenience alias for decoding a response when only the error/details matter.
public typealias ErrorResponse = APIResponse<EmptyData>
