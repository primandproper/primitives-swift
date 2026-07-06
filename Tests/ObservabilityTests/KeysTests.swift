import Foundation
import Testing

@testable import Observability

/// Pins every `Keys` constant to its literal string value so that drift from platform-go's
/// `observability/keys` package (or an accidental value change during a refactor) is caught by
/// the test suite instead of silently breaking cross-language span/log field parity.
@Suite("Keys parity")
struct KeysParityTests {

  @Test("tracing keys")
  func tracingKeys() {
    #expect(Keys.spanID == "span.id")
    #expect(Keys.traceID == "trace.id")
  }

  @Test("error keys")
  func errorKeys() {
    #expect(Keys.error == "error")
  }

  @Test("service / identity keys")
  func serviceIdentityKeys() {
    #expect(Keys.serviceName == "service_name")
    #expect(Keys.name == "name")
  }

  @Test("request / response keys")
  func requestResponseKeys() {
    #expect(Keys.requestID == "request.id")
    #expect(Keys.requestMethod == "request.method")
    #expect(Keys.requestURI == "request.uri")
    #expect(Keys.requestHeaders == "request.headers")
    #expect(Keys.responseStatus == "response.status")
    #expect(Keys.responseHeaders == "response.headers")
    #expect(Keys.url == "url")
    #expect(Keys.urlQuery == "url.query")
    #expect(Keys.reason == "reason")
    #expect(Keys.searchQuery == "search_query")
    #expect(Keys.validationError == "validation_error")
  }

  @Test("user / session keys")
  func userSessionKeys() {
    #expect(Keys.requesterID == "request.made_by")
    #expect(Keys.userID == "user.id")
    #expect(Keys.username == "user.username")
    #expect(Keys.userIsServiceAdmin == "user.is_admin")
    #expect(Keys.activeAccountID == "active_account.id")
  }

  @Test("query filtering keys")
  func queryFilteringKeys() {
    #expect(Keys.filterLimit == "query_filter.limit")
    #expect(Keys.filterCursor == "query_filter.cursor")
    #expect(Keys.filterSortBy == "query_filter.sort_by")
    #expect(Keys.filterCreatedAfter == "query_filter.created_after")
    #expect(Keys.filterCreatedBefore == "query_filter.created_before")
    #expect(Keys.filterUpdatedAfter == "query_filter.updated_after")
    #expect(Keys.filterUpdatedBefore == "query_filter.updated_before")
    #expect(Keys.filterIsNil == "query_filter.is_nil")
  }

  @Test("client environment keys")
  func clientEnvironmentKeys() {
    #expect(Keys.os == "os")
    #expect(Keys.isBot == "is_bot")
    #expect(Keys.isMobile == "is_mobile")
  }

  @Test("search / indexing keys")
  func searchIndexingKeys() {
    #expect(Keys.indexName == "index.name")
    #expect(Keys.useDatabase == "use_database")
  }

  @Test("email keys")
  func emailKeys() {
    #expect(Keys.emailSubject == "email.subject")
    #expect(Keys.emailToAddress == "email.to_address")
    #expect(Keys.emailFromAddress == "email.from_address")
  }

  @Test("misc domain keys")
  func miscDomainKeys() {
    #expect(Keys.connectionURL == "connection_url")
    #expect(Keys.topic == "topic")
    #expect(Keys.filename == "filename")
    #expect(Keys.length == "length")
  }
}
