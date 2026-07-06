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
  public static let name = "name"

  // Request / response
  public static let requestID = "request.id"
  public static let requestMethod = "request.method"
  public static let requestURI = "request.uri"
  public static let requestHeaders = "request.headers"
  public static let responseStatus = "response.status"
  public static let responseHeaders = "response.headers"
  public static let url = "url"
  public static let urlQuery = "url.query"
  public static let reason = "reason"
  public static let searchQuery = "search_query"
  public static let validationError = "validation_error"

  // User / session
  public static let requesterID = "request.made_by"
  public static let userID = "user.id"
  public static let username = "user.username"
  public static let userIsServiceAdmin = "user.is_admin"
  public static let activeAccountID = "active_account.id"

  // Query filtering
  public static let filterLimit = "query_filter.limit"
  public static let filterCursor = "query_filter.cursor"
  public static let filterSortBy = "query_filter.sort_by"
  public static let filterCreatedAfter = "query_filter.created_after"
  public static let filterCreatedBefore = "query_filter.created_before"
  public static let filterUpdatedAfter = "query_filter.updated_after"
  public static let filterUpdatedBefore = "query_filter.updated_before"
  public static let filterIsNil = "query_filter.is_nil"

  // Client environment
  public static let os = "os"
  public static let isBot = "is_bot"
  public static let isMobile = "is_mobile"

  // Search / indexing
  public static let indexName = "index.name"
  public static let useDatabase = "use_database"

  // Email
  public static let emailSubject = "email.subject"
  public static let emailToAddress = "email.to_address"
  public static let emailFromAddress = "email.from_address"

  // Misc domain keys carried over from platform-go
  public static let connectionURL = "connection_url"
  public static let topic = "topic"
  public static let filename = "filename"
  public static let length = "length"
}
