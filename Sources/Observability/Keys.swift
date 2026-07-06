/// Canonical attribute/field key names, ported from platform-go's `observability/keys`. Using shared
/// constants keeps span attributes and log fields consistently named across the toolkit (and across
/// languages). The HTTP/session keys apply equally to client-side `URLSession` work.
public enum Keys {
  // Tracing
  public static let spanID = "span.id"
  public static let traceID = "trace.id"

  // Errors
  public static let error = "error"
  // OTel-semconv exception attributes recorded by `Span.recordError`.
  public static let exceptionType = "exception.type"
  public static let exceptionMessage = "exception.message"

  // Service / identity
  public static let serviceName = "service_name"

  // Request / response
  public static let requestID = "request.id"
  public static let requestMethod = "request.method"
  public static let requestURI = "request.uri"
  public static let requestHeaders = "request.headers"
  public static let responseStatus = "response.status"
  public static let responseHeaders = "response.headers"
  public static let path = "path"
  public static let urlQuery = "url.query"

  // User / session
  public static let requesterID = "request.made_by"
  public static let userID = "user.id"
  public static let username = "user.username"
  public static let userIsServiceAdmin = "user.is_admin"
  public static let activeAccountID = "active_account.id"

  // Query filtering
  public static let filterLimit = "filter.limit"
  public static let filterCursor = "filter.cursor"
  public static let filterSortBy = "filter.sort_by"
  public static let filterCreatedAfter = "filter.created_after"

  // Client environment
  public static let os = "os"
  public static let isBot = "is_bot"
  public static let isMobile = "is_mobile"

  // Misc domain keys carried over from platform-go
  public static let connectionURL = "connection.url"
  public static let topic = "topic"
  public static let filename = "filename"
}
