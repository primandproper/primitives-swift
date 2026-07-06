import Foundation

/// URL-safe, **unpadded** base64, the encoding JWT (RFC 7515 §2, "base64url") uses for its header,
/// payload, and signature segments.
///
/// This is deliberately *not* the padded ``Cryptography`` `Base64URL` helper: JWS segments carry no `=`
/// padding, and Foundation's `Data(base64Encoded:)` rejects unpadded input. Rather than couple this
/// module to `Cryptography` (which itself prefers reaching for primitives directly), we keep a small
/// self-contained codec here — the module stays decoupled and depends only on system frameworks.
enum Base64URLNoPad {
  /// Decodes unpadded base64url, returning `nil` on any byte outside the URL-safe alphabet.
  ///
  /// **Strict (RFC 7515 §2 / Go's `base64.RawURLEncoding`).** Only `A–Z a–z 0–9 - _` are accepted. A
  /// standard-alphabet `+`/`/`, *any* `=` (this encoding is unpadded — even trailing padding is
  /// invalid), or whitespace is rejected. The previous `replacingOccurrences` path passed a stray `+`
  /// or `/` straight through to Foundation's standard-alphabet decoder, accepting JWS segments RFC 7515
  /// and Go reject; this validates the alphabet up front instead.
  static func decode(_ string: String) -> Data? {
    var s = ""
    s.reserveCapacity(string.utf8.count)
    for byte in string.utf8 {
      switch byte {
      case UInt8(ascii: "A")...UInt8(ascii: "Z"),
        UInt8(ascii: "a")...UInt8(ascii: "z"),
        UInt8(ascii: "0")...UInt8(ascii: "9"):
        s.unicodeScalars.append(UnicodeScalar(byte))
      case UInt8(ascii: "-"):
        s.append("+")
      case UInt8(ascii: "_"):
        s.append("/")
      default:
        // `+`, `/`, `=`, whitespace, or anything else: not in RawURLEncoding's alphabet.
        return nil
      }
    }
    // Restore the padding Foundation's (padded) decoder requires. A remainder of 1 is impossible for
    // real base64url and produces an invalid `"X==="`-style tail that Foundation then rejects.
    let remainder = s.count % 4
    if remainder != 0 {
      s += String(repeating: "=", count: 4 - remainder)
    }
    return Data(base64Encoded: s)
  }

  static func encode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
