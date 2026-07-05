import Foundation

/// URL-safe, **unpadded** base64, the encoding JWT (RFC 7515 §2, "base64url") uses for its header,
/// payload, and signature segments.
///
/// This is deliberately *not* the padded ``Cryptography`` `Base64URL` helper: JWS segments carry no `=`
/// padding, and Foundation's `Data(base64Encoded:)` rejects unpadded input. Rather than couple this
/// module to `Cryptography` (which itself prefers reaching for primitives directly), we keep a small
/// self-contained codec here — the module stays decoupled and depends only on system frameworks.
enum Base64URLNoPad {
  static func decode(_ string: String) -> Data? {
    var s =
      string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    // Restore the padding Foundation's decoder requires.
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
