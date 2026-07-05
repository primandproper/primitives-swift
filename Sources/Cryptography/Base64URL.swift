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
  static func decode(_ string: String) -> Data? {
    let standard =
      string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    return Data(base64Encoded: standard)
  }
}
