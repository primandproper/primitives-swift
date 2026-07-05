import Foundation

/// Cryptographically secure random string/byte generation, ported from platform-go's `random`
/// package (`Generator` interface).
///
/// **Security posture.** Go reads from `crypto/rand`. The faithful Apple-platform equivalent is
/// `SecRandomCopyBytes` (Security framework), which draws from the system CSPRNG — that is what
/// ``StandardGenerator`` uses, so these values are safe for secrets, tokens, and nonces. We
/// deliberately do *not* use `SystemRandomNumberGenerator` here: while it is CSPRNG-backed on
/// current Apple OSes, that is an implementation detail rather than a documented guarantee, and
/// this API exists precisely to promise cryptographic strength. (The non-secret slice helper in
/// `Slices.swift` is the one place we accept `SystemRandomNumberGenerator`, matching Go's use of
/// `math/rand` there.)
///
/// **Dropped from the Go surface.** The Go methods take a `context.Context` and emit an
/// observability span per call; there is no context or tracer in this standalone module, so those
/// parameters are gone. The `Must*` variants (which `panic` on error) are also omitted — in Swift
/// the idiomatic "this must not fail" is `try!` at the call site, which reads better than a
/// bespoke trapping wrapper. The `crypto/rand`-availability `init()` self-check is likewise
/// dropped; `SecRandomCopyBytes` reports failure per call, which we surface as a thrown error.
public protocol RandomGenerator: Sendable {
  /// Returns `length` cryptographically random bytes.
  func generateRawBytes(length: Int) throws -> [UInt8]
  /// Returns `length` random bytes rendered as a lowercase hex string (`2 * length` characters).
  func generateHexEncodedString(length: Int) throws -> String
  /// Returns `length` random bytes rendered as standard (padded) RFC 4648 base32.
  func generateBase32EncodedString(length: Int) throws -> String
  /// Returns `length` random bytes rendered as unpadded, URL-safe base64 (Go's `RawURLEncoding`).
  func generateBase64EncodedString(length: Int) throws -> String
}

/// Failure reading from the system CSPRNG. Wraps the `OSStatus` returned by `SecRandomCopyBytes`.
public struct RandomGenerationError: Error, Equatable, Sendable {
  /// The non-success status returned by `SecRandomCopyBytes`.
  public let status: OSStatus
  public init(status: OSStatus) { self.status = status }
}

/// Thrown when a negative length is requested. Go's `make([]byte, length)` panics on a negative
/// length; we surface it as a recoverable error instead of trapping.
public struct InvalidLengthError: Error, Equatable, Sendable {
  public let length: Int
  public init(length: Int) { self.length = length }
}
