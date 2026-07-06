import CryptoKit
import Foundation

/// The HMAC hash function backing a TOTP, ported from `github.com/pquerna/otp`'s `otp.Algorithm`.
///
/// RFC 6238 permits SHA-1, SHA-256, and SHA-512; SHA-1 is the near-universal default
/// (Google-Authenticator-compatible) and is what the Go `totp.Validate`/`GenerateCode` shortcuts use.
/// All three live in CryptoKit, so generated codes match the Go side exactly.
public enum TOTPAlgorithm: String, Sendable, CaseIterable {
  case sha1
  case sha256
  case sha512
}

/// Errors surfaced by ``TOTP``. The messages mirror platform-go's `authentication/totp` sentinels
/// (`ErrCodeRequired`, `ErrInvalidCode`) so telemetry text lines up across the two ports.
public enum TOTPError: Error, Equatable, Sendable {
  /// TOTP is enabled but the caller supplied an empty code. Mirrors Go's `ErrCodeRequired`.
  case codeRequired
  /// The code did not validate against the secret for the given time (within the skew window).
  /// Mirrors Go's `ErrInvalidCode`.
  case invalidCode
  /// The shared secret was not valid base32. In Go the underlying library error is swallowed by
  /// `totp.Validate` (surfacing as a plain non-match); this port names it explicitly rather than
  /// masquerading a malformed secret as a wrong code.
  case invalidSecret
}

extension TOTPError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .codeRequired: return "TOTP code required but not provided"
    case .invalidCode: return "invalid TOTP code"
    case .invalidSecret: return "TOTP secret is not valid base32"
    }
  }
}

/// A TOTP (RFC 6238) generator and verifier, ported from platform-go's `authentication/totp`
/// (which delegates to `github.com/pquerna/otp`).
///
/// The Go package exposes only a `Verifier.Verify(secret, code)` using the library's
/// Google-Authenticator-compatible defaults (period 30, 6 digits, SHA-1, ±1 period of skew). This port
/// preserves those defaults *and* the underlying parameters so it can also **generate** codes — the
/// piece an authenticator-app UI needs — and be verified against RFC 6238's published test vectors.
///
/// - Important: The core is **time-injected**: ``generate(secret:at:)`` and ``verify(code:secret:at:)``
///   take the reference `Date` explicitly and never read the wall clock, so tests can pin fixed-time
///   vectors. The `Now` conveniences read `Date()` at the edge, exactly as Go's shortcuts call
///   `time.Now().UTC()`.
public struct TOTP: Sendable {
  /// Seconds each code is valid for. RFC 6238 default: 30.
  public let period: Int
  /// Number of digits in the code. Default: 6.
  public let digits: Int
  /// HMAC hash function. Default: SHA-1.
  public let algorithm: TOTPAlgorithm
  /// Number of periods before/after the reference time that also validate. `1` accepts the adjacent
  /// windows (the pquerna default); `0` accepts only the exact window.
  public let skew: Int

  public init(period: Int = 30, digits: Int = 6, algorithm: TOTPAlgorithm = .sha1, skew: Int = 1) {
    precondition(period > 0, "TOTP period must be positive")
    precondition(digits > 0 && digits <= 9, "TOTP digits must be 1...9")
    precondition(skew >= 0, "TOTP skew must be non-negative")
    self.period = period
    self.digits = digits
    self.algorithm = algorithm
    self.skew = skew
  }

  // MARK: - Generation

  /// Generates the code for `secret` at `date`. Mirrors `totp.GenerateCode(secret, t)`.
  /// - Throws: ``TOTPError/invalidSecret`` if `secret` is not valid base32.
  public func generate(secret: String, at date: Date) throws -> String {
    guard let key = Base32.decode(secret) else { throw TOTPError.invalidSecret }
    return code(key: key, counter: counter(for: date))
  }

  /// Convenience reading the current wall clock — the only place this type touches `Date()`, matching
  /// Go's `time.Now().UTC()` shortcut.
  public func generateNow(secret: String) throws -> String {
    try generate(secret: secret, at: Date())
  }

  // MARK: - Verification

  /// Verifies `code` against `secret` at `date`, scanning the skew window. Mirrors platform-go's
  /// `Verifier.Verify` semantics.
  /// - Throws: ``TOTPError/codeRequired`` if `code` is empty, ``TOTPError/invalidCode`` if it does not
  ///   validate, or ``TOTPError/invalidSecret`` if `secret` is not valid base32.
  public func verify(code: String, secret: String, at date: Date) throws {
    if code.isEmpty { throw TOTPError.codeRequired }
    guard try isValid(code: code, secret: secret, at: date) else {
      throw TOTPError.invalidCode
    }
  }

  /// `Bool`-returning verification for control flow. Unlike ``verify(code:secret:at:)`` this does not
  /// distinguish "empty" from "wrong" — an empty code is simply invalid. Still throws on a malformed
  /// secret.
  public func isValid(code: String, secret: String, at date: Date) throws -> Bool {
    guard let key = Base32.decode(secret) else { throw TOTPError.invalidSecret }

    let candidate = code.trimmingCharacters(in: .whitespacesAndNewlines)
    // pquerna's hotp.ValidateCustom rejects a wrong-length passcode outright.
    guard candidate.utf8.count == digits else { return false }

    let center = counter(for: date)
    var counters: [UInt64] = [center]
    // Match pquerna's ordering: center, then +1/-1, +2/-2, … up to skew.
    if skew > 0 {
      for i in 1...skew {
        counters.append(center &+ UInt64(i))
        counters.append(center &- UInt64(i))
      }
    }

    let candidateBytes = Array(candidate.utf8)
    for c in counters {
      let generated = self.code(key: key, counter: c)
      if constantTimeEqual(Array(generated.utf8), candidateBytes) {
        return true
      }
    }
    return false
  }

  /// Convenience verifying against the current wall clock.
  public func verifyNow(code: String, secret: String) throws {
    try verify(code: code, secret: secret, at: Date())
  }

  // MARK: - Core (HOTP, RFC 4226)

  /// Time-step counter: `floor(unixSeconds / period)`, matching pquerna's
  /// `uint64(math.Floor(float64(t.Unix()) / float64(period)))`.
  private func counter(for date: Date) -> UInt64 {
    let seconds = floor(date.timeIntervalSince1970)
    // Clamp pre-1970 dates to the epoch (counter 0): a negative interval would trap `UInt64`'s
    // failable-less `Double` initializer. The wall-clock callers never reach here, but an explicit
    // `at:` vector could hand us a pre-epoch `Date`, and a crash is never the right answer for one.
    guard seconds >= 0 else { return 0 }
    return UInt64(floor(seconds / Double(period)))
  }

  /// The RFC 4226 dynamic-truncation HOTP value for `counter`, formatted to `digits`.
  private func code(key: Data, counter: UInt64) -> String {
    var bigEndian = counter.bigEndian
    let counterBytes = withUnsafeBytes(of: &bigEndian) { Data($0) }

    let mac = hmac(key: key, message: counterBytes)

    // Dynamic truncation (RFC 4226 §5.4).
    let offset = Int(mac[mac.count - 1] & 0x0F)
    let binary =
      (UInt32(mac[offset] & 0x7F) << 24)
      | (UInt32(mac[offset + 1]) << 16)
      | (UInt32(mac[offset + 2]) << 8)
      | UInt32(mac[offset + 3])

    let modulus = UInt32(pow(10, Double(digits)))
    let value = Int(binary % modulus)
    // Zero-padded to `digits`, matching Go's `Digits.Format` / `fmt.Sprintf("%0*d", …)`.
    return String(format: "%0\(digits)d", value)
  }

  private func hmac(key: Data, message: Data) -> [UInt8] {
    let symmetricKey = SymmetricKey(data: key)
    switch algorithm {
    case .sha1:
      return Array(
        CryptoKit.HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetricKey))
    case .sha256:
      return Array(CryptoKit.HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey))
    case .sha512:
      return Array(CryptoKit.HMAC<SHA512>.authenticationCode(for: message, using: symmetricKey))
    }
  }
}

/// Length-independent, content-constant-time byte comparison, mirroring Go's
/// `subtle.ConstantTimeCompare` used by pquerna when matching codes. Guards the 2FA path against a
/// timing side channel.
func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
  guard lhs.count == rhs.count else { return false }
  var difference: UInt8 = 0
  for i in 0..<lhs.count {
    difference |= lhs[i] ^ rhs[i]
  }
  return difference == 0
}
