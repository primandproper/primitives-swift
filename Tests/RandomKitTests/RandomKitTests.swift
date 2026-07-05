import Foundation
import Testing

@testable import RandomKit

@Suite("StandardGenerator raw bytes")
struct RawBytesTests {
  @Test("returns exactly the requested number of bytes")
  func length() throws {
    let bytes = try StandardGenerator().generateRawBytes(length: 32)
    #expect(bytes.count == 32)
  }

  @Test("zero length yields an empty, non-throwing result")
  func zeroLength() throws {
    #expect(try StandardGenerator().generateRawBytes(length: 0).isEmpty)
  }

  @Test("negative length throws InvalidLengthError")
  func negativeLength() {
    #expect(throws: InvalidLengthError(length: -1)) {
      try StandardGenerator().generateRawBytes(length: -1)
    }
  }

  @Test("two draws differ (distribution sanity)")
  func distinct() throws {
    let g = StandardGenerator()
    let a = try g.generateRawBytes(length: 32)
    let b = try g.generateRawBytes(length: 32)
    #expect(a != b)
  }
}

@Suite("StandardGenerator encoded strings")
struct EncodedStringTests {
  @Test("hex output is 2*length lowercase hex characters")
  func hex() throws {
    let s = try StandardGenerator().generateHexEncodedString(length: 16)
    #expect(s.count == 32)
    let allowed = Set("0123456789abcdef")
    #expect(s.allSatisfy { allowed.contains($0) })
  }

  @Test("base32 output uses the standard alphabet and padding")
  func base32() throws {
    let s = try StandardGenerator().generateBase32EncodedString(length: 32)
    #expect(!s.isEmpty)
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=")
    #expect(s.allSatisfy { allowed.contains($0) })
  }

  @Test("base64 output is URL-safe and unpadded")
  func base64() throws {
    let s = try StandardGenerator().generateBase64EncodedString(length: 32)
    #expect(!s.isEmpty)
    #expect(!s.contains("="))
    #expect(!s.contains("+"))
    #expect(!s.contains("/"))
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    #expect(s.allSatisfy { allowed.contains($0) })
  }
}

@Suite("Encoders pinned to known vectors")
struct EncoderVectorTests {
  @Test("hex matches Go's encoding/hex")
  func hexVector() {
    #expect(StandardGenerator.hexEncode([0xde, 0xad, 0xbe, 0xef]) == "deadbeef")
    #expect(StandardGenerator.hexEncode([]) == "")
  }

  @Test("base32 matches Go's StdEncoding")
  func base32Vector() {
    #expect(Base32.standardEncode(Array("foobar".utf8)) == "MZXW6YTBOI======")
    #expect(Base32.standardEncode(Array("f".utf8)) == "MY======")
    #expect(Base32.standardEncode([]) == "")
  }

  @Test("base64 matches Go's RawURLEncoding")
  func base64Vector() {
    // Standard base64 of {0xff,0xff} is "//8="; URL-safe + unpadded is "__8".
    #expect(StandardGenerator.base64RawURLEncode([0xff, 0xff]) == "__8")
    #expect(StandardGenerator.base64RawURLEncode([]) == "")
  }
}

@Suite("Free functions and default generator")
struct FreeFunctionTests {
  @Test("package-level helpers delegate to the default generator")
  func freeFunctions() throws {
    #expect(try generateRawBytes(length: 8).count == 8)
    #expect(try generateHexEncodedString(length: 8).count == 16)
    #expect(try !generateBase32EncodedString(length: 8).isEmpty)
    #expect(try !generateBase64EncodedString(length: 8).isEmpty)
  }
}

@Suite("NoopGenerator")
struct NoopGeneratorTests {
  @Test("returns empty results and never fails")
  func empties() throws {
    let g = NoopGenerator()
    #expect(try g.generateRawBytes(length: 32).isEmpty)
    #expect(try g.generateHexEncodedString(length: 32) == "")
    #expect(try g.generateBase32EncodedString(length: 32) == "")
    #expect(try g.generateBase64EncodedString(length: 32) == "")
  }
}

@Suite("randomElement")
struct RandomElementTests {
  @Test("returns a member of a non-empty collection")
  func member() {
    let words = ["The", "FitnessGram", "Pacer", "Test"]
    let picked = randomElement(from: words)
    #expect(picked != nil)
    #expect(words.contains(picked!))
  }

  @Test("returns nil for an empty collection instead of trapping")
  func empty() {
    #expect(randomElement(from: [String]()) == nil)
    #expect(randomElement(from: [Int]()) == nil)
  }
}
