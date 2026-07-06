import Foundation

/// URL-safe, **padded** base64, matching Go's `encoding/base64.URLEncoding`.
///
/// The Go AES implementation encodes ciphertext with `base64.URLEncoding` (the URL alphabet `-`/`_`,
/// *with* `=` padding). Foundation's `Data.base64EncodedString()` uses the standard `+`/`/` alphabet
/// but the same padding, so translating the two alphabet characters — and reversing on decode — yields
/// byte-for-byte the same strings Go produces. Preserving this exactly keeps ciphertext wire-compatible
/// between the Go service and the iOS client.
enum Base64URL {
  static func encode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
  }

  /// Decodes URL-safe base64, returning `nil` for malformed input (mirroring Go's decode error path,
  /// which the caller maps to ``EncryptionError/invalidCiphertextEncoding``).
  ///
  /// **Strict alphabet (RFC 4648 §5 / Go's `base64.URLEncoding`).** Only the URL-safe alphabet is
  /// accepted: `A–Z a–z 0–9 - _`, with `=` permitted *solely* as a trailing padding run. A standard-
  /// alphabet `+` or `/`, or a `=` sitting mid-string, is rejected outright — Go's `URLEncoding`
  /// decoder does the same (those bytes are not in its alphabet), so leniently translating them (as the
  /// old `replacingOccurrences` path did) would have accepted ciphertext Go rejects.
  static func decode(_ string: String) -> Data? {
    var seenPadding = false
    for byte in string.utf8 {
      switch byte {
      case UInt8(ascii: "="):
        seenPadding = true
      case UInt8(ascii: "A")...UInt8(ascii: "Z"),
        UInt8(ascii: "a")...UInt8(ascii: "z"),
        UInt8(ascii: "0")...UInt8(ascii: "9"),
        UInt8(ascii: "-"), UInt8(ascii: "_"):
        // A data character after a padding `=` means the padding sat mid-string — reject, as Go does.
        if seenPadding { return nil }
      default:
        // `+`, `/`, whitespace, or any other non-alphabet byte: rejected (Go's URLEncoding rejects it).
        return nil
      }
    }

    let standard =
      string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    // Foundation's decoder still enforces correct length/padding on the (now-validated) alphabet.
    return Data(base64Encoded: standard)
  }
}
