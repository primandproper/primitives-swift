import Foundation

/// URL-safe, **padded** base64, matching Go's `encoding/base64.URLEncoding`.
///
/// `gorilla/securecookie` — which platform-go's cookie `Manager` wraps — encodes both the inner
/// payload and the outer envelope with `base64.URLEncoding` (the URL alphabet `-`/`_`, *with* `=`
/// padding). Foundation's `Data.base64EncodedString()` uses the standard `+`/`/` alphabet with the
/// same padding, so swapping the two alphabet characters (and reversing on decode) reproduces the
/// exact strings the Go side emits, keeping the signed envelope wire-compatible.
///
/// This mirrors ``Cryptography``'s `Base64URL`; it is duplicated here rather than shared so the
/// module stays self-contained (no cross-module dependency for a five-line helper).
enum Base64URL {
  static func encode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
  }

  /// Decodes URL-safe base64, returning `nil` for malformed input (the caller maps `nil` to
  /// ``CookieError/malformedValue``).
  static func decode(_ string: String) -> Data? {
    let standard =
      string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    return Data(base64Encoded: standard)
  }
}
