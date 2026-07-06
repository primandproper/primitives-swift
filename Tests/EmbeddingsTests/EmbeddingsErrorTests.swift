import Foundation
import Testing

@testable import Embeddings

@Suite("EmbeddingsError classification")
struct EmbeddingsErrorTests {
  @Test("401 and 403 map to authentication")
  func auth() {
    #expect(
      EmbeddingsError.classify(status: 401, message: "", model: "m", retryAfterHeader: nil)
        == .authentication)
    #expect(
      EmbeddingsError.classify(status: 403, message: "", model: "m", retryAfterHeader: nil)
        == .authentication)
  }

  @Test("404 maps to modelNotFound carrying the model")
  func notFound() {
    #expect(
      EmbeddingsError.classify(
        status: 404, message: "", model: "text-embedding-x", retryAfterHeader: nil)
        == .modelNotFound("text-embedding-x"))
  }

  @Test("429 maps to rateLimit, parsing Retry-After when present")
  func rateLimit() {
    #expect(
      EmbeddingsError.classify(status: 429, message: "", model: "m", retryAfterHeader: "5")
        == .rateLimit(retryAfter: 5))
    #expect(
      EmbeddingsError.classify(status: 429, message: "", model: "m", retryAfterHeader: nil)
        == .rateLimit(retryAfter: nil))
  }

  @Test("Retry-After parses both delta-seconds and HTTP-date forms")
  func retryAfterForms() {
    #expect(EmbeddingsError.parseRetryAfter("30") == 30)
    #expect(EmbeddingsError.parseRetryAfter(nil) == nil)
    #expect(EmbeddingsError.parseRetryAfter("garbage") == nil)

    let target = "Wed, 21 Oct 2015 07:29:00 GMT"
    let now = Date(timeIntervalSince1970: 1_445_412_480)  // 2015-10-21 07:28:00 GMT
    #expect(EmbeddingsError.parseRetryAfter(target, now: now) == 60)
  }

  @Test("400 routes a model-not-found message to modelNotFound, else invalidRequest")
  func badRequest() {
    #expect(
      EmbeddingsError.classify(
        status: 400, message: "The model `foo` does not exist", model: "foo", retryAfterHeader: nil)
        == .modelNotFound("foo"))
    #expect(
      EmbeddingsError.classify(
        status: 400, message: "bad params", model: "m", retryAfterHeader: nil)
        == .invalidRequest("bad params"))
  }

  @Test("an unmapped status falls through to provider")
  func other() {
    #expect(
      EmbeddingsError.classify(status: 503, message: "down", model: "m", retryAfterHeader: nil)
        == .provider(status: 503, message: "down"))
  }
}
