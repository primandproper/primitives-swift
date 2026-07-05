import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A ``QRCodeBuilder`` that renders TOTP QR codes with CoreImage, ported from platform-go's
/// unexported `builder` (constructed via `NewBuilder`).
///
/// Go composed `boombuler/barcode` + `image/png`: encode the `otpauth` URI as a QR barcode, scale it
/// to 256×256, PNG-encode it, then base64 it behind a `data:image/png;base64,` prefix. This port
/// does the CoreImage-native equivalent:
///
/// 1. `CIQRCodeGenerator` renders the URI to a 1-module-per-pixel `CIImage`.
/// 2. The image is upscaled with nearest-neighbor sampling (so module edges stay crisp) to roughly
///    ``pixelSize`` on a side, then rasterized to a `CGImage` via a `CIContext`.
/// 3. `ImageIO` encodes the `CGImage` to PNG bytes, which are base64-wrapped into a data URI.
///
/// Two knobs Go hardcoded are exposed as defaulted initializer parameters — ``correctionLevel``
/// (Go's `qr.L`) and ``pixelSize`` (Go's 256) — giving the CoreImage-native error-correction seam
/// without changing default behavior. `Sendable`: it stores only value types; the non-`Sendable`
/// `CIContext` is created per call inside the method, never stored.
public struct TOTPQRCodeBuilder: QRCodeBuilder {
  /// The service name embedded as the `issuer` label/parameter in the `otpauth` URI.
  public let issuer: Issuer
  /// Error-correction level fed to `CIQRCodeGenerator`. Defaults to ``ErrorCorrectionLevel/low`` to
  /// match Go's hardcoded `qr.L`.
  public let correctionLevel: ErrorCorrectionLevel
  /// Approximate side length, in pixels, of the rendered PNG. Defaults to 256 to match Go's scale.
  public let pixelSize: Int

  private static let dataURIPrefix = "data:image/png;base64,"

  public init(
    issuer: Issuer,
    correctionLevel: ErrorCorrectionLevel = .low,
    pixelSize: Int = 256
  ) {
    self.issuer = issuer
    self.correctionLevel = correctionLevel
    self.pixelSize = pixelSize
  }

  public func buildQRCode(
    username: String,
    twoFactorSecret: String
  ) throws(QRCodeError) -> String {
    let otpauthURI = try Self.makeOTPAuthURI(
      issuer: issuer, username: username, secret: twoFactorSecret)
    let pngData = try renderPNG(from: otpauthURI)
    return Self.dataURIPrefix + pngData.base64EncodedString()
  }

  /// Assembles the standard `otpauth://totp/{issuer}:{username}?secret=...&issuer=...` URI.
  ///
  /// Explicit percent-encoding replaces Go's `url.PathEscape`/`url.Values.Encode`, so
  /// issuers/usernames/secrets containing spaces or reserved characters (`&`, `?`, `#`, …) produce a
  /// valid, correctly-parsed URI. We deliberately do *not* use `URLComponents.queryItems`: its setter
  /// leaves `&`, `+`, and `=` unescaped inside values, which would silently corrupt a secret like
  /// `SECRET&123` into two query parameters. Instead each component is escaped against the RFC 3986
  /// unreserved set (plus `:` in the label, which the TOTP spec keeps literal and Go's `PathEscape`
  /// leaves alone). Kept `static`/`internal` so tests can assert the URI directly, the way Go's test
  /// captured the encoded string.
  static func makeOTPAuthURI(
    issuer: Issuer,
    username: String,
    secret: String
  ) throws(QRCodeError) -> String {
    // RFC 3986 unreserved characters — everything else (including sub-delimiters like `&`) is escaped.
    var unreserved = CharacterSet.alphanumerics
    unreserved.insert(charactersIn: "-._~")

    // The label keeps its `issuer:username` colon literal, matching the TOTP convention.
    var labelAllowed = unreserved
    labelAllowed.insert(":")

    guard
      let label = "\(issuer.rawValue):\(username)".addingPercentEncoding(
        withAllowedCharacters: labelAllowed),
      let escapedSecret = secret.addingPercentEncoding(withAllowedCharacters: unreserved),
      let escapedIssuer = issuer.rawValue.addingPercentEncoding(withAllowedCharacters: unreserved)
    else {
      throw .otpauthURIConstructionFailed
    }

    return "otpauth://totp/\(label)?secret=\(escapedSecret)&issuer=\(escapedIssuer)"
  }

  /// Runs the CoreImage → ImageIO pipeline, throwing the step-specific ``QRCodeError`` on failure.
  private func renderPNG(from content: String) throws(QRCodeError) -> Data {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(content.utf8)
    filter.correctionLevel = correctionLevel.rawValue

    // `outputImage` is nil when the content exceeds QR capacity — Go's `qr.Encode` error.
    guard let baseImage = filter.outputImage else {
      throw .encodingFailed
    }

    let extent = baseImage.extent
    guard extent.width > 0, extent.height > 0 else {
      throw .encodingFailed
    }

    // Upscale to ~pixelSize with nearest-neighbor sampling so modules stay hard-edged rather than
    // blurred by the default bilinear interpolation.
    let scale = CGFloat(pixelSize) / extent.width
    let scaledImage = baseImage
      .samplingNearest()
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

    let context = CIContext()
    guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
      throw .renderingFailed
    }

    return try encodePNG(cgImage)
  }

  /// Encodes a `CGImage` to PNG bytes via `ImageIO` — the cross-platform (iOS + macOS) path that
  /// avoids pulling in UIKit/AppKit.
  private func encodePNG(_ cgImage: CGImage) throws(QRCodeError) -> Data {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw .pngEncodingFailed
    }

    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw .pngEncodingFailed
    }

    return data as Data
  }
}
