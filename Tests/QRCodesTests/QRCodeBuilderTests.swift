import Foundation
import ImageIO
import Testing

@testable import QRCodes

/// Strips the `data:image/png;base64,` prefix and decodes the payload to raw PNG bytes, failing the
/// test if the URI isn't shaped as expected.
private func decodePNG(from dataURI: String) throws -> Data {
  let prefix = "data:image/png;base64,"
  let base64 = try #require(
    dataURI.hasPrefix(prefix) ? String(dataURI.dropFirst(prefix.count)) : nil,
    "expected a data:image/png;base64 URI")
  return try #require(Data(base64Encoded: base64), "payload should be valid base64")
}

/// Reads the pixel width of a PNG via ImageIO, without decoding the whole bitmap.
private func pixelWidth(of png: Data) -> Int? {
  guard
    let source = CGImageSourceCreateWithData(png as CFData, nil),
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
    let width = properties[kCGImagePropertyPixelWidth] as? Int
  else { return nil }
  return width
}

/// The 8-byte PNG signature.
private let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

@Suite("TOTPQRCodeBuilder.buildQRCode")
struct TOTPQRCodeBuilderTests {
  @Test("a known input yields a non-empty PNG data URI")
  func happyPath() throws {
    let builder = TOTPQRCodeBuilder(issuer: "Acme")

    let result = try builder.buildQRCode(
      username: "user@example.com", twoFactorSecret: "JBSWY3DPEHPK3PXP")

    #expect(result.hasPrefix("data:image/png;base64,"))
    let png = try decodePNG(from: result)
    #expect(!png.isEmpty)
    // The bytes must actually be a PNG, not just non-empty base64.
    #expect(Array(png.prefix(8)) == pngSignature)
    // Default pixelSize is 256; nearest-neighbor scaling lands within a pixel of it.
    let width = try #require(pixelWidth(of: png))
    #expect(abs(width - 256) <= 1)
  }

  @Test("pixelSize controls the rendered dimensions")
  func respectsPixelSize() throws {
    let small = try TOTPQRCodeBuilder(issuer: "Acme", pixelSize: 128)
      .buildQRCode(username: "user", twoFactorSecret: "JBSWY3DPEHPK3PXP")
    let large = try TOTPQRCodeBuilder(issuer: "Acme", pixelSize: 512)
      .buildQRCode(username: "user", twoFactorSecret: "JBSWY3DPEHPK3PXP")

    let smallWidth = try #require(pixelWidth(of: decodePNG(from: small)))
    let largeWidth = try #require(pixelWidth(of: decodePNG(from: large)))
    #expect(abs(smallWidth - 128) <= 1)
    #expect(abs(largeWidth - 512) <= 1)
  }

  @Test("the error-correction level is fed through to the generated code")
  func respectsErrorCorrectionLevel() throws {
    // Same content and size; only the EC level differs. `L` and `H` add very different amounts of
    // recovery data, so the resulting QR matrices — and thus the PNG bytes — must differ.
    func code(_ level: ErrorCorrectionLevel) throws -> Data {
      try decodePNG(
        from: TOTPQRCodeBuilder(issuer: "Acme", correctionLevel: level)
          .buildQRCode(username: "user@example.com", twoFactorSecret: "JBSWY3DPEHPK3PXP"))
    }

    let low = try code(.low)
    let high = try code(.high)
    #expect(!low.isEmpty)
    #expect(!high.isEmpty)
    #expect(low != high)
  }

  @Test("every error-correction level maps to its CoreImage inputCorrectionLevel string")
  func errorCorrectionLevelRawValues() {
    #expect(ErrorCorrectionLevel.low.rawValue == "L")
    #expect(ErrorCorrectionLevel.medium.rawValue == "M")
    #expect(ErrorCorrectionLevel.quartile.rawValue == "Q")
    #expect(ErrorCorrectionLevel.high.rawValue == "H")
  }

  @Test("reserved characters in issuer/username/secret still produce a valid PNG")
  func reservedCharactersDoNotBreakGeneration() throws {
    let builder = TOTPQRCodeBuilder(issuer: "My & App")

    let result = try builder.buildQRCode(username: "user name", twoFactorSecret: "SECRET&123")

    let png = try decodePNG(from: result)
    #expect(Array(png.prefix(8)) == pngSignature)
  }

  @Test("content exceeding QR capacity throws encodingFailed")
  func oversizedContentThrows() {
    let builder = TOTPQRCodeBuilder(issuer: "Acme")

    // A username far beyond the ~2.9KB QR capacity forces CIQRCodeGenerator to emit no image.
    #expect(throws: QRCodeError.encodingFailed) {
      _ = try builder.buildQRCode(
        username: String(repeating: "a", count: 4000), twoFactorSecret: "JBSWY3DPEHPK3PXP")
    }
  }

  @Test("the otpauth URI escapes issuer, username, and secret containing reserved characters")
  func otpauthURIEscaping() throws {
    let uri = try TOTPQRCodeBuilder.makeOTPAuthURI(
      issuer: "My & App", username: "user name", secret: "SECRET&123")

    let parsed = try #require(URLComponents(string: uri), "the URI must be well-formed")
    #expect(parsed.scheme == "otpauth")
    #expect(parsed.host == "totp")
    // The reserved characters must round-trip out of the query, not split it into extra params.
    #expect(parsed.queryItems?.first { $0.name == "issuer" }?.value == "My & App")
    #expect(parsed.queryItems?.first { $0.name == "secret" }?.value == "SECRET&123")
    // The label decodes back to the literal "issuer:username".
    #expect(parsed.path == "/My & App:user name")
  }
}

@Suite("NoopQRCodeBuilder")
struct NoopQRCodeBuilderTests {
  @Test("returns an empty string and never throws")
  func returnsEmptyString() throws {
    let builder = NoopQRCodeBuilder()

    let result = try builder.buildQRCode(
      username: "user@example.com", twoFactorSecret: "JBSWY3DPEHPK3PXP")

    #expect(result.isEmpty)
  }

  @Test("conforms to QRCodeBuilder so it drops in for the real builder")
  func conformsToProtocol() throws {
    let builder: any QRCodeBuilder = NoopQRCodeBuilder()

    let result = try builder.buildQRCode(username: "user", twoFactorSecret: "secret")

    #expect(result.isEmpty)
  }
}
