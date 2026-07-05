import Testing

@testable import Cryptography

/// Known-answer tests. The inputs and expected digests are copied verbatim from the Go
/// `_test.go` files so the Swift port is verified against the *same* vectors. Note the Go tests hash
/// `t.Name()`, which for a subtest is the full `"<Func>/<sub>"` path — e.g.
/// `"Test_sha256Hasher_Hash/standard"` — so those exact strings are reproduced here.
@Suite("Hashing known-answer vectors")
struct HashingKnownAnswerTests {
  @Test("SHA-256 matches the Go vector")
  func sha256() {
    let result = SHA256Hasher().hash("Test_sha256Hasher_Hash/standard")
    #expect(result == "f469799cfc8eb5c3fa03e2ec4faf3c1b9a4c3a1c0ac3557a2f963e598cea695f")
  }

  @Test("SHA-512 matches the Go vector")
  func sha512() {
    let result = SHA512Hasher().hash("Test_sha512Hasher_Hash/standard")
    #expect(
      result
        == "5928cb042c3cc8dc19dce0eb7caa4ad440e7c4b429503c42ef2fa3dc0fee9232a85db9276c690809f70c92ea68deb255bbd5dd1e9ecd71ade0db9eaaab205c21"
    )
  }

  @Test("Adler-32 matches the Go vector")
  func adler32() {
    let result = Adler32Hasher().hash("Test_adler32Hasher_Hash/standard")
    #expect(result == "c7060c2b")
  }

  @Test("CRC-64 (ISO) matches the Go vector")
  func crc64() {
    let result = CRC64Hasher().hash("Test_crc64Hasher_Hash/standard")
    #expect(result == "cee81309a5f73f5c")
  }

  @Test("FNV-1a (128-bit) matches the Go vector")
  func fnv() {
    let result = FNVHasher().hash("Test_fnvHasher_Hash/standard")
    #expect(result == "780242af2cb9fb3c85ad54840e9411ec")
  }
}

@Suite("Hashing properties")
struct HashingPropertyTests {
  private let hashers: [Hasher] = [
    SHA256Hasher(), SHA512Hasher(), Adler32Hasher(), CRC64Hasher(), FNVHasher(),
  ]

  @Test("empty input is total (no crash) and deterministic")
  func emptyAndDeterministic() {
    for hasher in hashers {
      let a = hasher.hash("")
      let b = hasher.hash("")
      #expect(a == b)
      #expect(!a.isEmpty)
    }
  }

  @Test("digests are lowercase hex")
  func lowercaseHex() {
    let hexChars = Set("0123456789abcdef")
    for hasher in hashers {
      let digest = hasher.hash("the quick brown fox")
      #expect(digest.allSatisfy { hexChars.contains($0) })
    }
  }

  @Test("distinct inputs produce distinct digests")
  func distinctInputs() {
    for hasher in hashers {
      #expect(hasher.hash("alpha") != hasher.hash("beta"))
    }
  }

  @Test("well-known empty-string digests for the cryptographic hashers")
  func emptyStringCryptographic() {
    // Canonical empty-string digests, independent of the Go origin.
    #expect(
      SHA256Hasher().hash("")
        == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(
      SHA512Hasher().hash("")
        == "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
    )
  }
}
