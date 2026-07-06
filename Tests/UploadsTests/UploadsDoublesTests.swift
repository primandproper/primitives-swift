import Foundation
import Testing

@testable import Uploads

@Suite("Uploads doubles")
struct UploadsDoublesTests {
  @Test("NoopUploader discards writes and reports nothing exists")
  func noopUploader() async throws {
    let uploader: any Uploader = NoopUploader()
    try await uploader.save("a.txt", data: Data("hi".utf8))
    #expect(try await uploader.read("a.txt") == Data())
    #expect(try await uploader.exists("a.txt") == false)
    try await uploader.delete("a.txt")
  }

  @Test("UploaderMock records calls and returns defaults when unscripted")
  func mockUploaderRecords() async throws {
    let mock = UploaderMock()
    try await mock.save("a.txt", data: Data("x".utf8), options: SaveOptions(contentType: "t"))
    _ = try await mock.read("a.txt")
    _ = try await mock.exists("a.txt")
    try await mock.delete("a.txt")

    let saveCalls = await mock.saveCalls
    #expect(saveCalls.count == 1)
    #expect(saveCalls.first?.path == "a.txt")
    #expect(saveCalls.first?.options.contentType == "t")
    #expect(await mock.readCalls == ["a.txt"])
    #expect(await mock.existsCalls == ["a.txt"])
    #expect(await mock.deleteCalls == ["a.txt"])
  }

  @Test("UploaderMock setReadHandler scripts the return post-init")
  func mockUploaderScripts() async throws {
    let mock = UploaderMock()
    await mock.setReadHandler { path in Data("echo:\(path)".utf8) }
    let read = try await mock.read("k")
    #expect(read == Data("echo:k".utf8))
  }

  @Test("UploaderMock propagates a throwing handler")
  func mockUploaderThrows() async {
    let mock = UploaderMock(saveHandler: { _, _, _ in throw UploadsError.invalidPath("nope") })
    await #expect(throws: UploadsError.invalidPath("nope")) {
      try await mock.save("k", data: Data())
    }
  }

  @Test("NoopPresignedUploader reports a synthetic success")
  func noopPresigned() async throws {
    let uploader: any PresignedUploader = NoopPresignedUploader()
    let response = try await uploader.upload(
      PresignedUploadRequest(url: URL(string: "https://x.test/o")!, body: Data("x".utf8)))
    #expect(response.statusCode == 200)
    #expect(response.etag == nil)
  }

  @Test("PresignedUploaderMock records requests and returns a scripted response")
  func mockPresigned() async throws {
    let mock = PresignedUploaderMock()
    await mock.setUploadHandler { _ in PresignedUploadResponse(statusCode: 204, etag: "e") }

    let request = PresignedUploadRequest(
      url: URL(string: "https://x.test/o")!, method: .post, body: Data("x".utf8))
    let response = try await mock.upload(request)

    #expect(response.statusCode == 204)
    #expect(response.etag == "e")
    let calls = await mock.uploadCalls
    #expect(calls == [request])
  }

  @Test("PresignedUploaderMock with no handler returns a default success")
  func mockPresignedDefault() async throws {
    let mock = PresignedUploaderMock()
    let response = try await mock.upload(
      PresignedUploadRequest(url: URL(string: "https://x.test/o")!, body: Data()))
    #expect(response.statusCode == 200)
  }
}
