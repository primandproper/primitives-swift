import Testing

@testable import Identifiers

@Suite("Identifier.new")
struct IdentifierNewTests {
  @Test("produces a non-empty, 20-character xid string")
  func length() {
    let id = Identifier.new()
    #expect(!id.isEmpty)
    #expect(id.count == 20)
  }

  @Test("every character is in the xid base32-hex alphabet")
  func alphabet() {
    let allowed = Set("0123456789abcdefghijklmnopqrstuv")
    let id = Identifier.new()
    #expect(id.allSatisfy { allowed.contains($0) })
  }

  @Test("successive IDs are distinct")
  func uniqueness() {
    let ids = Set((0..<1000).map { _ in Identifier.new() })
    #expect(ids.count == 1000)
  }

  @Test("generated IDs validate as their own round-trip")
  func selfValidating() {
    for _ in 0..<100 {
      #expect(Identifier.isValid(Identifier.new()))
    }
  }
}

@Suite("Identifier.validate / isValid")
struct IdentifierValidateTests {
  @Test("a freshly generated ID validates without throwing")
  func happyPath() throws {
    try Identifier.validate(Identifier.new())
  }

  @Test("wrong length is invalid")
  func wrongLength() {
    #expect(!Identifier.isValid(""))
    #expect(!Identifier.isValid("tooshort"))
    #expect(!Identifier.isValid(String(repeating: "0", count: 21)))
  }

  @Test("characters outside the alphabet are invalid")
  func badCharacters() {
    // 'w', 'x', 'y', 'z' and uppercase are all outside the base32-hex alphabet.
    #expect(!Identifier.isValid(String(repeating: "w", count: 20)))
    #expect(!Identifier.isValid(String(repeating: "A", count: 20)))
  }

  @Test("a non-canonical trailing character is invalid")
  func nonCanonicalTail() {
    // All-zero xid is canonical; mutating the final char to one whose low bits can't round-trip
    // through encode must fail the canonical-tail check.
    var chars = Array(String(repeating: "0", count: 20))
    chars[19] = "1"
    #expect(!Identifier.isValid(String(chars)))
  }

  @Test("validate throws InvalidIdentifierError carrying the bad value")
  func throwsWithValue() {
    #expect(throws: InvalidIdentifierError(value: "nope")) {
      try Identifier.validate("nope")
    }
  }
}

@Suite("XID encoder")
struct XIDEncoderTests {
  @Test("all-zero raw ID encodes to twenty zeros and validates")
  func allZeroVector() {
    let zeros = [UInt8](repeating: 0, count: 12)
    let encoded = XIDGenerator.encode(zeros)
    #expect(encoded == String(repeating: "0", count: 20))
    #expect(XIDGenerator.isValidIDString(encoded))
  }

  @Test("all-ones raw ID encodes to a known-boundary vector")
  func allOnesVector() {
    let ones = [UInt8](repeating: 0xFF, count: 12)
    let encoded = XIDGenerator.encode(ones)
    #expect(encoded.count == 20)
    // dst[0] = encoding[0xFF >> 3 = 31] = 'v'; dst[19] = encoding[(0xFF << 4) & 0x1f = 0x10 = 16] = 'g'.
    #expect(encoded.first == "v")
    #expect(encoded.last == "g")
  }

  @Test("timestamp prefix is sortable across generations")
  func sortablePrefix() {
    // The first four bytes are a big-endian seconds timestamp, so two IDs minted moments apart
    // must be lexically ordered by their leading characters (equal or ascending).
    let first = Identifier.new()
    let second = Identifier.new()
    #expect(first.prefix(6) <= second.prefix(6))
  }
}
