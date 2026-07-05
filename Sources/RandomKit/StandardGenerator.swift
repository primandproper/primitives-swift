import Foundation
import Security

/// The production ``RandomGenerator``, backed by the system CSPRNG via `SecRandomCopyBytes`.
/// Equivalent to Go's `standardGenerator` reading from `crypto/rand.Reader`.
public struct StandardGenerator: RandomGenerator {
  public init() {}

  public func generateRawBytes(length: Int) throws -> [UInt8] {
    guard length >= 0 else { throw InvalidLengthError(length: length) }
    guard length > 0 else { return [] }

    var bytes = [UInt8](repeating: 0, count: length)
    let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
      SecRandomCopyBytes(kSecRandomDefault, length, buffer.baseAddress!)
    }
    guard status == errSecSuccess else { throw RandomGenerationError(status: status) }
    return bytes
  }

  public func generateHexEncodedString(length: Int) throws -> String {
    Self.hexEncode(try generateRawBytes(length: length))
  }

  public func generateBase32EncodedString(length: Int) throws -> String {
    Base32.standardEncode(try generateRawBytes(length: length))
  }

  public func generateBase64EncodedString(length: Int) throws -> String {
    Self.base64RawURLEncode(try generateRawBytes(length: length))
  }

  // MARK: - Encoders (internal so tests can pin them to known vectors)

  /// Lowercase hex, matching Go's `encoding/hex.EncodeToString`.
  static func hexEncode(_ bytes: [UInt8]) -> String {
    let digits: [UInt8] = Array("0123456789abcdef".utf8)
    var out = [UInt8]()
    out.reserveCapacity(bytes.count * 2)
    for byte in bytes {
      out.append(digits[Int(byte >> 4)])
      out.append(digits[Int(byte & 0x0f)])
    }
    return String(decoding: out, as: UTF8.self)
  }

  /// Unpadded, URL-safe base64, matching Go's `encoding/base64.RawURLEncoding`. Foundation only
  /// offers standard base64 with padding, so we translate the alphabet (`+`->`-`, `/`->`_`) and
  /// strip the `=` padding.
  static func base64RawURLEncode(_ bytes: [UInt8]) -> String {
    Data(bytes)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

/// A one-shot default generator so callers can generate a value without wiring up a ``StandardGenerator``.
/// Mirrors Go's package-level `defaultGenerator` and its free functions. `any RandomGenerator` is
/// `Sendable` (the protocol requires it), so this global constant is concurrency-safe.
public let defaultGenerator: any RandomGenerator = StandardGenerator()

/// Free function mirroring Go's `random.GenerateRawBytes`.
public func generateRawBytes(length: Int) throws -> [UInt8] {
  try defaultGenerator.generateRawBytes(length: length)
}

/// Free function mirroring Go's `random.GenerateHexEncodedString`.
public func generateHexEncodedString(length: Int) throws -> String {
  try defaultGenerator.generateHexEncodedString(length: length)
}

/// Free function mirroring Go's `random.GenerateBase32EncodedString`.
public func generateBase32EncodedString(length: Int) throws -> String {
  try defaultGenerator.generateBase32EncodedString(length: length)
}

/// Free function mirroring Go's `random.GenerateBase64EncodedString`.
public func generateBase64EncodedString(length: Int) throws -> String {
  try defaultGenerator.generateBase64EncodedString(length: length)
}
