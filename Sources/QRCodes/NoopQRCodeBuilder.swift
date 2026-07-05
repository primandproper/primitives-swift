/// A ``QRCodeBuilder`` that generates nothing, ported from platform-go's `qrcodes/noop` subpackage.
///
/// Go isolates the no-op in its own package (`noop.NewBuilder`); Swift folds it into the `QRCodes`
/// module as a distinct type, since there's no import cycle or naming pressure forcing a separate
/// module (same choice the `Retry` port made for `NoopRetryPolicy`). Use it wherever a
/// ``QRCodeBuilder`` is required but real QR generation is undesired — DI wiring, tests, or callers
/// that render codes elsewhere.
///
/// Matching Go's `BuildQRCode` returning `("", nil)`, this returns an empty string and never throws.
public struct NoopQRCodeBuilder: QRCodeBuilder {
  public init() {}

  public func buildQRCode(username: String, twoFactorSecret: String) throws(QRCodeError) -> String {
    ""
  }
}
