import Testing

@testable import LLM

@Suite("LLMError classification")
struct LLMErrorTests {
  @Test("401 and 403 map to authentication")
  func auth() {
    #expect(LLMError.classify(status: 401, message: "", model: "m", retryAfterHeader: nil) == .authentication)
    #expect(LLMError.classify(status: 403, message: "", model: "m", retryAfterHeader: nil) == .authentication)
  }

  @Test("404 maps to modelNotFound carrying the model")
  func notFound() {
    #expect(
      LLMError.classify(status: 404, message: "", model: "gpt-x", retryAfterHeader: nil)
        == .modelNotFound("gpt-x"))
  }

  @Test("429 maps to rateLimit, parsing Retry-After when present")
  func rateLimit() {
    #expect(
      LLMError.classify(status: 429, message: "", model: "m", retryAfterHeader: "5")
        == .rateLimit(retryAfter: 5))
    #expect(
      LLMError.classify(status: 429, message: "", model: "m", retryAfterHeader: nil)
        == .rateLimit(retryAfter: nil))
  }

  @Test("400 routes a model-not-found message to modelNotFound, else invalidRequest")
  func badRequest() {
    #expect(
      LLMError.classify(
        status: 400, message: "The model `foo` does not exist", model: "foo", retryAfterHeader: nil)
        == .modelNotFound("foo"))
    #expect(
      LLMError.classify(status: 400, message: "bad params", model: "m", retryAfterHeader: nil)
        == .invalidRequest("bad params"))
  }

  @Test("an unmapped status falls through to provider")
  func other() {
    #expect(
      LLMError.classify(status: 503, message: "down", model: "m", retryAfterHeader: nil)
        == .provider(status: 503, message: "down"))
  }
}
