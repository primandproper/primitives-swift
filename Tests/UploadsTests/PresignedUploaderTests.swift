import CircuitBreaking
import Foundation
import Observability
import Testing

@testable import Uploads

@Suite("URLSessionPresignedUploader")
struct PresignedUploaderTests {
  @Test("a PUT presigned upload sends the right verb, headers, and body")
  func requestShape() async throws {
    let host = uniqueStubHost()
    let box = CapturedBox()
    UploadsStubURLProtocol.register(host: host, box: box) { _ in
      .respond(status: 200, body: Data(), headers: ["ETag": "\"abc123\""])
    }
    defer { UploadsStubURLProtocol.unregister(host) }

    let uploader = URLSessionPresignedUploader(
      session: uploadsStubbedSession(), observer: recordingObserver("test"))

    let url = URL(string: "https://\(host)/bucket/key.txt?X-Amz-Signature=deadbeef")!
    let body = Data("the object body".utf8)
    let response = try await uploader.upload(
      PresignedUploadRequest(
        url: url, method: .put, body: body,
        contentType: "text/plain", cacheControl: "max-age=60"))

    #expect(response.statusCode == 200)
    // ETag is unquoted for the caller.
    #expect(response.etag == "abc123")

    let captured = try #require(box.value)
    #expect(captured.method == "PUT")
    #expect(captured.url == url.absoluteString)
    #expect(captured.contentType == "text/plain")
    #expect(captured.cacheControl == "max-age=60")
    #expect(captured.body == body)
  }

  @Test("SaveOptions-built request omits empty headers")
  func fromOptions() async throws {
    let host = uniqueStubHost()
    let box = CapturedBox()
    UploadsStubURLProtocol.register(host: host, box: box) { _ in
      .respond(status: 201, body: Data(), headers: [:])
    }
    defer { UploadsStubURLProtocol.unregister(host) }

    let uploader = URLSessionPresignedUploader(
      session: uploadsStubbedSession(), observer: recordingObserver("test"))

    let request = PresignedUploadRequest(
      url: URL(string: "https://\(host)/o")!, method: .post,
      body: Data("x".utf8), options: SaveOptions())
    let response = try await uploader.upload(request)

    #expect(response.statusCode == 201)
    let captured = try #require(box.value)
    #expect(captured.method == "POST")
    #expect(captured.contentType == nil)
    #expect(captured.cacheControl == nil)
  }

  @Test("a non-2xx status throws uploadFailed carrying the body message")
  func nonSuccessThrows() async {
    let host = uniqueStubHost()
    let box = CapturedBox()
    UploadsStubURLProtocol.register(host: host, box: box) { _ in
      .respond(status: 403, body: Data("SignatureDoesNotMatch".utf8), headers: [:])
    }
    defer { UploadsStubURLProtocol.unregister(host) }

    let uploader = URLSessionPresignedUploader(
      session: uploadsStubbedSession(), observer: recordingObserver("test"))

    await #expect(throws: UploadsError.uploadFailed(status: 403, message: "SignatureDoesNotMatch"))
    {
      _ = try await uploader.upload(
        PresignedUploadRequest(url: URL(string: "https://\(host)/o")!, body: Data("x".utf8)))
    }
  }

  @Test("an open circuit breaker refuses the upload without touching the network")
  func circuitBrokenFailsFast() async {
    let host = uniqueStubHost()
    let box = CapturedBox()
    UploadsStubURLProtocol.register(host: host, box: box) { _ in
      .respond(status: 200, body: Data(), headers: [:])
    }
    defer { UploadsStubURLProtocol.unregister(host) }

    let uploader = URLSessionPresignedUploader(
      session: uploadsStubbedSession(),
      observer: recordingObserver("test"),
      circuitBreaker: AlwaysOpenBreaker())

    await #expect(throws: UploadsError.circuitBroken) {
      _ = try await uploader.upload(
        PresignedUploadRequest(url: URL(string: "https://\(host)/o")!, body: Data("x".utf8)))
    }
    // Nothing reached the transport.
    #expect(box.value == nil)
  }

  @Test("a transport-level URLError propagates raw")
  func transportErrorPropagates() async {
    let host = uniqueStubHost()
    let box = CapturedBox()
    UploadsStubURLProtocol.register(host: host, box: box) { _ in
      .fail(URLError(.notConnectedToInternet))
    }
    defer { UploadsStubURLProtocol.unregister(host) }

    let uploader = URLSessionPresignedUploader(
      session: uploadsStubbedSession(), observer: recordingObserver("test"))

    await #expect(throws: (any Error).self) {
      _ = try await uploader.upload(
        PresignedUploadRequest(url: URL(string: "https://\(host)/o")!, body: Data("x".utf8)))
    }
  }
}

/// A breaker that is always open, to drive the fail-fast path.
private struct AlwaysOpenBreaker: CircuitBreaker {
  func recordFailure() async {}
  func recordSuccess() async {}
  func canProceed() async -> Bool { false }
}
