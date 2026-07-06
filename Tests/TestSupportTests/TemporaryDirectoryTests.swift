import Foundation
import Testing

@testable import TestSupport

@Suite("TemporaryDirectory")
struct TemporaryDirectoryTests {
  @Test("creates a real directory and cleans it up on remove()")
  func createsAndCleansUp() throws {
    let manager = FileManager.default
    let directory = try TemporaryDirectory(label: "createsAndCleansUp")

    var isDirectory: ObjCBool = false
    #expect(manager.fileExists(atPath: directory.url.path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)

    let written = try directory.write(Data("contents".utf8), to: "file.txt")
    #expect(manager.fileExists(atPath: written.path))

    try directory.remove()
    #expect(!manager.fileExists(atPath: directory.url.path))
  }

  @Test("remove() is idempotent")
  func removeIsIdempotent() throws {
    let directory = try TemporaryDirectory(label: "idempotent")
    try directory.remove()
    try directory.remove()
    #expect(!FileManager.default.fileExists(atPath: directory.url.path))
  }

  @Test("hands out distinct directories on each construction")
  func distinctDirectories() throws {
    let first = try TemporaryDirectory(label: "distinct")
    defer { try? first.remove() }
    let second = try TemporaryDirectory(label: "distinct")
    defer { try? second.remove() }
    #expect(first.url != second.url)
  }

  @Test("withTemporaryDirectory removes the directory even when the body throws")
  func scopedCleanup() {
    struct Boom: Error {}
    var captured: URL?
    #expect(throws: Boom.self) {
      try withTemporaryDirectory(label: "scoped") { url in
        captured = url
        throw Boom()
      }
    }
    let path = try! #require(captured).path
    #expect(!FileManager.default.fileExists(atPath: path))
  }
}
