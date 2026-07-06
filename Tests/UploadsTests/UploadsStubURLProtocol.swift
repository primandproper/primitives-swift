import Foundation
import os

/// What a stubbed upload should do when it reaches the fake transport.
enum UploadStubOutcome: Sendable {
  case respond(status: Int, body: Data, headers: [String: String])
  case fail(any Error & Sendable)
}

/// What the fake transport captured about the outgoing request, so a test can assert the presigned-upload
/// request *shape* (verb, headers, body) without a network.
struct CapturedUpload: Sendable, Equatable {
  var method: String
  var url: String
  var contentType: String?
  var cacheControl: String?
  var body: Data
  var headers: [String: String]
}

/// A hermetic `URLProtocol` stub so upload tests never hit the network. Handlers are keyed by request host
/// (each test mints a unique host) so parallel `swift-testing` cases can't clobber each other.
final class UploadsStubURLProtocol: URLProtocol, @unchecked Sendable {
  private struct Entry {
    let outcome: @Sendable (URLRequest) -> UploadStubOutcome
    let box: CapturedBox
  }

  private static let registry = OSAllocatedUnfairLock<[String: Entry]>(initialState: [:])

  static func register(
    host: String,
    box: CapturedBox,
    _ handler: @escaping @Sendable (URLRequest) -> UploadStubOutcome
  ) {
    registry.withLock { $0[host] = Entry(outcome: handler, box: box) }
  }

  static func unregister(_ host: String) {
    registry.withLock { $0[host] = nil }
  }

  private static func entry(for host: String) -> Entry? {
    registry.withLock { $0[host] }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let host = request.url?.host, let entry = UploadsStubURLProtocol.entry(for: host) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    // `URLSession.upload(for:from:)` moves the body onto the upload task's stream; `httpBody` on the
    // captured request is nil there, so read `httpBodyStream` when present.
    let body = UploadsStubURLProtocol.readBody(from: request)
    entry.box.capture(
      CapturedUpload(
        method: request.httpMethod ?? "",
        url: request.url?.absoluteString ?? "",
        contentType: request.value(forHTTPHeaderField: "Content-Type"),
        cacheControl: request.value(forHTTPHeaderField: "Cache-Control"),
        body: body,
        headers: request.allHTTPHeaderFields ?? [:]))

    switch entry.outcome(request) {
    case .respond(let status, let responseBody, let headers):
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: responseBody)
      client?.urlProtocolDidFinishLoading(self)
    case .fail(let error):
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}

  private static func readBody(from request: URLRequest) -> Data {
    if let body = request.httpBody {
      return body
    }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: bufferSize)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}

/// A thread-safe box the stub writes the captured request into for the test to inspect.
final class CapturedBox: @unchecked Sendable {
  private let state = OSAllocatedUnfairLock<CapturedUpload?>(initialState: nil)
  func capture(_ upload: CapturedUpload) { state.withLock { $0 = upload } }
  var value: CapturedUpload? { state.withLock { $0 } }
}

/// A `URLSession` wired to the upload stub transport.
func uploadsStubbedSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [UploadsStubURLProtocol.self]
  configuration.timeoutIntervalForRequest = 4
  configuration.timeoutIntervalForResource = 4
  return URLSession(configuration: configuration)
}

/// A unique stub host per test so parallel cases don't share handler state.
func uniqueStubHost() -> String { "\(UUID().uuidString.lowercased()).uploads.test" }
