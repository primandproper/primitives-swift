import Foundation

/// Generates QR codes for TOTP two-factor-authentication setup, ported from platform-go's
/// `qrcodes.Builder` interface.
///
/// Go's `BuildQRCode(ctx, username, twoFactorSecret) (string, error)` becomes a synchronous
/// `throws(QRCodeError)` method returning the same artifact: a base64-encoded `data:image/png`
/// URI ready to drop into an `<img src>` or a `UIImage`/`NSImage`. Two Go arguments are dropped:
///
/// - `context.Context` — Go carried it only to open an observability span; there is no async work
///   to cancel here (QR rendering is synchronous CPU work), so it is elided, mirroring how the
///   `Retry` port dropped `ctx` in favor of structured concurrency.
/// - The tracer/logger constructor arguments — this port is deliberately dependency-free: the
///   `QRCodes` target declares no package dependencies, relying only on the system
///   `CoreImage`/`ImageIO` frameworks, which Apple-platform autolinking pulls in from their `import`s
///   (no explicit `linkerSettings` needed). So it takes no `Observability` dependency; a caller that
///   wants a span can wrap the call.
///
/// The concrete implementation is ``TOTPQRCodeBuilder``; ``NoopQRCodeBuilder`` is the no-op used
/// for DI/tests. `Sendable` so a builder can be stored in a service or captured by a `Task`.
public protocol QRCodeBuilder: Sendable {
  /// Builds a QR code encoding the standard `otpauth://totp/...` URI for `username` and
  /// `twoFactorSecret`, returning it as a `data:image/png;base64,` URI. Throws ``QRCodeError`` if
  /// the content exceeds QR capacity or the image cannot be rendered/encoded.
  func buildQRCode(username: String, twoFactorSecret: String) throws(QRCodeError) -> String
}

/// Identifies the service that issued the TOTP secret, ported from Go's `type Issuer string`.
///
/// Go uses a named string type for type safety at the constructor boundary; the Swift analogue is a
/// thin `RawRepresentable` wrapper that is also `ExpressibleByStringLiteral`, so
/// `TOTPQRCodeBuilder(issuer: "Acme")` reads as cleanly as Go's `Issuer("Acme")`.
public struct Issuer: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
  public let rawValue: String

  public init(rawValue: String) { self.rawValue = rawValue }

  /// Convenience initializer so callers can write `Issuer("Acme")`.
  public init(_ rawValue: String) { self.rawValue = rawValue }

  public init(stringLiteral value: String) { self.rawValue = value }
}

/// QR-code error-correction level, mapped onto CoreImage's `CIQRCodeGenerator`
/// `inputCorrectionLevel`.
///
/// Go hardcoded `qr.L` (the lowest, densest level) inside `BuildQRCode`; CoreImage exposes the same
/// four ISO levels as single-character strings, so this port surfaces them as a configurable knob on
/// ``TOTPQRCodeBuilder`` while defaulting to ``low`` to stay behaviorally faithful to Go. Higher
/// levels tolerate more damage/occlusion at the cost of a denser (larger-module-count) code.
public enum ErrorCorrectionLevel: String, Sendable, CaseIterable {
  /// ~7% recovery. Matches Go's hardcoded `qr.L`.
  case low = "L"
  /// ~15% recovery.
  case medium = "M"
  /// ~25% recovery.
  case quartile = "Q"
  /// ~30% recovery.
  case high = "H"
}

/// Failure modes of ``TOTPQRCodeBuilder/buildQRCode(username:twoFactorSecret:)``, ported from the
/// three error returns Go's `BuildQRCode` produced (encode, scale, PNG-encode), plus a case for the
/// one step that cannot fail in Go — URI construction.
public enum QRCodeError: Error, Equatable {
  /// The `otpauth://` URI could not be assembled from the given inputs. Has no Go analogue
  /// (`url.Values`/`fmt.Sprintf` can't fail); guards the `URLComponents.string` optional here.
  case otpauthURIConstructionFailed
  /// `CIQRCodeGenerator` produced no image — most commonly because the content exceeds QR capacity.
  /// Analogue of Go's `qr.Encode` error.
  case encodingFailed
  /// The QR `CIImage` could not be rasterized to a `CGImage`. Analogue of Go's scale-step error.
  case renderingFailed
  /// The rendered image could not be encoded to PNG bytes. Analogue of Go's `png.Encode` error.
  case pngEncodingFailed
}
