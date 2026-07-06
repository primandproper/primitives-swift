import Foundation
import Testing

@testable import TestSupport

@Suite("StubURLProtocol")
struct StubURLProtocolTests {
  @Test("intercepts a URLSession request and returns the canned response")
  func intercepts() async throws {
    let token = "intercepts"
    let body = Data("hello".utf8)
    StubURLProtocol.register(
      token: token, response: .success(status: 201, body: body, headers: ["X-Test": "yes"]))
    defer { StubURLProtocol.unregister(token: token) }

    let session = StubURLProtocol.makeSession()
    let (data, response) = try await session.data(for: StubURLProtocol.request(token: token))

    let http = try #require(response as? HTTPURLResponse)
    #expect(http.statusCode == 201)
    #expect(http.value(forHTTPHeaderField: "X-Test") == "yes")
    #expect(data == body)
  }

  @Test("records the requests it saw for assertion after the fact")
  func recordsRequests() async throws {
    let token = "records"
    StubURLProtocol.register(token: token) { _ in .ok(body: Data("ok".utf8)) }
    defer { StubURLProtocol.unregister(token: token) }

    let session = StubURLProtocol.makeSession()
    var request = StubURLProtocol.request(
      token: token, url: URL(string: "https://example.test/submit")!)
    request.httpMethod = "POST"
    request.httpBody = Data("payload".utf8)
    _ = try await session.data(for: request)

    let captured = StubURLProtocol.capturedRequests(token: token)
    #expect(captured.count == 1)
    #expect(captured.first?.httpMethod == "POST")
    #expect(captured.first?.url?.path == "/submit")
    #expect(StubURLProtocol.body(of: captured[0]) == Data("payload".utf8))
  }

  @Test("propagates a stubbed failure as a thrown error")
  func propagatesFailure() async {
    let token = "fails"
    StubURLProtocol.register(token: token, response: .failure(URLError(.notConnectedToInternet)))
    defer { StubURLProtocol.unregister(token: token) }

    let session = StubURLProtocol.makeSession()
    await #expect(throws: URLError.self) {
      _ = try await session.data(for: StubURLProtocol.request(token: token))
    }
  }

  @Test("an unregistered token fails rather than hitting the network")
  func unregisteredFails() async {
    let session = StubURLProtocol.makeSession()
    await #expect(throws: (any Error).self) {
      _ = try await session.data(for: StubURLProtocol.request(token: "never-registered"))
    }
  }
}
