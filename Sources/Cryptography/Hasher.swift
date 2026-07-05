import Foundation

/// Hashes a string into a **lowercase hex-encoded** digest, ported from platform-go's
/// `cryptography/hashing.Hasher`.
///
/// The Go interface is `Hash(content string) (string, error)`. Every Go implementation only ever
/// returns a non-nil error from `hash.Hash.Write`, which — for all of Go's stdlib hashers — never
/// actually fails. Rather than carry a `throws` that can never throw into Swift, this protocol makes
/// `hash(_:)` non-throwing: it is a total function from `String` to hex digest. The wire contract is
/// preserved exactly — the output is the lowercase hex encoding of the raw digest bytes, byte-for-byte
/// what Go's `hex.EncodeToString(h.Sum(nil))` produces.
///
/// - Important: implementations vary in cryptographic strength, mirroring the Go package's own warning.
///   ``SHA256Hasher`` and ``SHA512Hasher`` are cryptographic hashes; ``Adler32Hasher``, ``CRC64Hasher``,
///   and ``FNVHasher`` are **non-cryptographic checksums** and MUST NOT be selected for security,
///   password, or tamper-resistance purposes. Choose the implementation deliberately.
public protocol Hasher: Sendable {
  /// Returns the lowercase hex-encoded digest of `content` (UTF-8 encoded before hashing, exactly as
  /// Go's `[]byte(content)`).
  func hash(_ content: String) -> String
}

/// Lowercase hex encoding of raw bytes, matching Go's `encoding/hex.EncodeToString`.
///
/// Kept as an internal helper (rather than reaching for `Data.hexEncodedString`, which Foundation does
/// not provide) so every hasher renders digests identically to the Go origin.
enum HexEncoding {
  private static let alphabet = Array("0123456789abcdef".utf8)

  static func encode<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    var out = [UInt8]()
    for b in bytes {
      out.append(alphabet[Int(b >> 4)])
      out.append(alphabet[Int(b & 0x0F)])
    }
    return String(decoding: out, as: UTF8.self)
  }
}
