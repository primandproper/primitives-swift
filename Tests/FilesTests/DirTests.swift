import Foundation
import Testing

@testable import Files

private struct Sample: Codable, Equatable {
  var name: String
  var count: Int
}

/// Lays out root/b/stuff.txt and root/c/whatever.txt, mirroring platform-go's `dir_test.go`
/// `buildTree` helper, and returns the root.
private func buildTree() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let b = root.appendingPathComponent("b")
  let c = root.appendingPathComponent("c")
  try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
  try "1\n2\n3\n".write(
    to: b.appendingPathComponent("stuff.txt"), atomically: true, encoding: .utf8)
  try "x\ny\n".write(
    to: c.appendingPathComponent("whatever.txt"), atomically: true, encoding: .utf8)
  return root
}

@Suite("Dir")
struct DirTests {
  @Test("resolves names against the root directory")
  func resolvesNames() async throws {
    let root = try buildTree()
    let dir = try Dir(root: .custom(root.appendingPathComponent("b")))

    var out: [String] = []
    for try await line in try dir.lines("stuff.txt") { out.append(line) }
    #expect(out == ["1", "2", "3"])
  }

  @Test("rejects a name that escapes the root via ..")
  func rejectsDotDotEscape() throws {
    let root = try buildTree()
    let dir = try Dir(root: .custom(root.appendingPathComponent("b")))

    #expect(throws: FilesError.pathEscapesRoot("../c/whatever.txt")) {
      _ = try dir.resolve("../c/whatever.txt")
    }
    #expect(throws: FilesError.pathEscapesRoot("../../etc/passwd")) {
      _ = try dir.resolve("../../etc/passwd")
    }
  }

  @Test("rejects an absolute name that overrides the root")
  func rejectsAbsoluteOverride() throws {
    let root = try buildTree()
    let dir = try Dir(root: .custom(root.appendingPathComponent("b")))

    #expect(throws: FilesError.pathEscapesRoot("/etc/passwd")) {
      _ = try dir.resolve("/etc/passwd")
    }
  }

  @Test("accepts a nested, non-escaping relative name")
  func acceptsNestedName() throws {
    let root = try buildTree()
    let dir = try Dir(root: .custom(root.appendingPathComponent("b")))

    let resolved = try dir.resolve("nested/file.txt")
    #expect(resolved == root.appendingPathComponent("b/nested/file.txt").path)
  }

  @Test("sub descends into a child directory without mutating the original")
  func subDescendsWithoutMutating() throws {
    let root = try buildTree()
    let dir = try Dir(root: .custom(root))

    let sub = try dir.sub("b")
    #expect(dir.path == root.path)
    #expect(sub.path == root.appendingPathComponent("b").path)
  }

  @Test("sub rejects a name that would escape the root")
  func subRejectsEscape() throws {
    let root = try buildTree()
    let dir = try Dir(root: .custom(root.appendingPathComponent("b")))

    #expect(throws: FilesError.pathEscapesRoot("../c")) {
      _ = try dir.sub("../c")
    }
  }

  @Test("resolve feeds decodeFile")
  func resolveFeedsDecodeFile() throws {
    let root = try buildTree()
    let configPath = root.appendingPathComponent("b/config.json")
    try #"{"name":"platform","count":2}"#.write(to: configPath, atomically: true, encoding: .utf8)

    let dir = try Dir(root: .custom(root.appendingPathComponent("b")))
    let got = try decodeFile(Sample.self, atPath: dir.resolve("config.json"), contentType: .json)
    #expect(got == Sample(name: "platform", count: 2))
  }

  @Test("chunks works relative to the root")
  func chunksRelativeToRoot() async throws {
    let root = try buildTree()
    let dir = try Dir(root: .custom(root.appendingPathComponent("b")))

    var out: [[String]] = []
    for try await chunk in try dir.chunks("stuff.txt", size: 2) { out.append(chunk) }
    #expect(out == [["1", "2"], ["3"]])
  }

  @Test("sliceLines works relative to the root")
  func sliceLinesRelativeToRoot() async throws {
    let root = try buildTree()
    let dir = try Dir(root: .custom(root.appendingPathComponent("b")))

    let got = try await dir.sliceLines("stuff.txt", offset: 1, count: 2)
    #expect(got == ["2", "3"])
  }

  @Test("opening a Dir on a non-directory throws notADirectory")
  func openOnNonDirectoryThrows() throws {
    let root = try buildTree()
    let filePath = root.appendingPathComponent("b/stuff.txt")

    #expect(throws: (any Error).self) {
      _ = try Dir(root: .custom(filePath))
    }
  }

  @Test("sub to a non-directory throws notADirectory")
  func subToNonDirectoryThrows() throws {
    let root = try buildTree()
    let dir = try Dir(root: .custom(root.appendingPathComponent("b")))

    #expect(throws: (any Error).self) {
      _ = try dir.sub("stuff.txt")
    }
  }
}
