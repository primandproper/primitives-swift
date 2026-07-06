import Foundation
import Observability
import Testing

@testable import Uploads

/// A `FileManagerUploader` rooted at a fresh temp directory, cleaned up by the caller via the returned URL.
private func makeUploader() -> (uploader: FileManagerUploader, root: URL) {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("uploads-test-\(UUID().uuidString)", isDirectory: true)
  let uploader = FileManagerUploader(root: root, observer: recordingObserver("test"))
  return (uploader, root)
}

@Suite("FileManagerUploader")
struct FileManagerUploaderTests {
  @Test("save/read/delete round-trip through a nested key")
  func roundTrip() async throws {
    let (uploader, root) = makeUploader()
    defer { try? FileManager.default.removeItem(at: root) }

    let payload = Data("the object body".utf8)
    let key = "nested/path/object.txt"

    try await uploader.save(key, data: payload)
    #expect(try await uploader.exists(key))

    let read = try await uploader.read(key)
    #expect(read == payload)

    try await uploader.delete(key)
    #expect(try await uploader.exists(key) == false)
  }

  @Test("save honors options without failing (content type not persisted locally)")
  func saveWithOptions() async throws {
    let (uploader, root) = makeUploader()
    defer { try? FileManager.default.removeItem(at: root) }

    try await uploader.save(
      "a.bin", data: Data([0x00, 0x01]),
      options: SaveOptions(contentType: "application/octet-stream", cacheControl: "max-age=60"))
    #expect(try await uploader.exists("a.bin"))
  }

  @Test("reading a missing object throws notFound")
  func readMissing() async {
    let (uploader, root) = makeUploader()
    defer { try? FileManager.default.removeItem(at: root) }

    await #expect(throws: UploadsError.notFound("nope.txt")) {
      _ = try await uploader.read("nope.txt")
    }
  }

  @Test("deleting a missing object is a quiet no-op")
  func deleteMissing() async throws {
    let (uploader, root) = makeUploader()
    defer { try? FileManager.default.removeItem(at: root) }
    // Should not throw.
    try await uploader.delete("never-written.txt")
  }

  @Test(
    "a traversal key is rejected before any filesystem access",
    arguments: [
      "../escape.txt",
      "nested/../../escape.txt",
      "a/b/../../../../etc/passwd",
    ])
  func rejectsTraversal(key: String) async {
    let (uploader, root) = makeUploader()
    defer { try? FileManager.default.removeItem(at: root) }

    await #expect(throws: UploadsError.pathEscapesRoot(key)) {
      try await uploader.save(key, data: Data("x".utf8))
    }
  }

  @Test("an empty key is rejected as invalid")
  func rejectsEmpty() async {
    let (uploader, root) = makeUploader()
    defer { try? FileManager.default.removeItem(at: root) }

    await #expect(throws: UploadsError.invalidPath("")) {
      try await uploader.save("", data: Data("x".utf8))
    }
  }

  @Test("a traversal that lands back inside the root is still allowed")
  func innerTraversalAllowed() async throws {
    let (uploader, root) = makeUploader()
    defer { try? FileManager.default.removeItem(at: root) }

    // `a/b/../c.txt` resolves to `a/c.txt`, which stays under the root — not a traversal escape.
    try await uploader.save("a/b/../c.txt", data: Data("ok".utf8))
    #expect(try await uploader.read("a/c.txt") == Data("ok".utf8))
  }

  @Test("no file escapes the root on disk after a rejected traversal")
  func nothingWrittenOutsideRoot() async {
    let (uploader, root) = makeUploader()
    defer { try? FileManager.default.removeItem(at: root) }

    let sibling = root.deletingLastPathComponent().appendingPathComponent("escape.txt")
    try? FileManager.default.removeItem(at: sibling)

    await #expect(throws: (any Error).self) {
      try await uploader.save("../escape.txt", data: Data("pwned".utf8))
    }
    #expect(FileManager.default.fileExists(atPath: sibling.path) == false)
  }
}
