import CryptoKit
import Foundation

/// A ``Hasher`` backed by SHA-256, ported from platform-go's `cryptography/hashing/sha256`.
///
/// Go builds the digest with `crypto/sha256`; here we use Apple **CryptoKit** (`SHA256`), which is the
/// clean, hardware-accelerated analogue. The output is identical: SHA-256 is a fixed standard, so the
/// lowercase hex encoding of the 32-byte digest matches Go byte-for-byte (see the known-answer test).
public struct SHA256Hasher: Hasher {
  public init() {}

  public func hash(_ content: String) -> String {
    let digest = SHA256.hash(data: Data(content.utf8))
    return HexEncoding.encode(digest)
  }
}

/// A ``Hasher`` backed by SHA-512, ported from platform-go's `cryptography/hashing/sha512`.
///
/// As with ``SHA256Hasher``, this swaps Go's `crypto/sha512` for CryptoKit's `SHA512`. SHA-512 is a
/// fixed standard, so the 64-byte digest — and its hex encoding — match the Go origin exactly.
public struct SHA512Hasher: Hasher {
  public init() {}

  public func hash(_ content: String) -> String {
    let digest = SHA512.hash(data: Data(content.utf8))
    return HexEncoding.encode(digest)
  }
}
