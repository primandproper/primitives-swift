import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deterministic fixture builders, adapting platform-go's `testutils` image/data helpers
/// (`BuildArbitraryImage`, `BuildArbitraryImagePNGBytes`) and its example key constants to the iOS
/// client. Everything here is a pure function of its inputs — no randomness, no clock — so a test
/// asserting on the bytes is stable across runs.
public enum TestData {
  /// A 32-byte secret, mirroring platform-go `testutils.Example32ByteKey`. Useful for exercising
  /// AES-256 / key-sized-input code paths without inventing a key per test.
  public static let example32ByteKey = "HEREISA32CHARSECRETWHICHISMADEUP"

  /// A 64-byte secret, mirroring platform-go `testutils.Example64ByteKey`.
  public static let example64ByteKey =
    "HEREISA64CHARSECRETWHICHISMADEUPHEREISA64CHARSECRETWHICHISMADEUP"

  /// `count` deterministic bytes: byte `i` is `(i + seed) mod 256`. A drop-in for tests that just need
  /// some non-empty, reproducible payload (uploads, hashing, compression) — the port's answer to
  /// reaching for random fixture bytes.
  public static func deterministicBytes(count: Int, seed: UInt8 = 0) -> Data {
    guard count > 0 else { return Data() }
    return Data((0..<count).map { UInt8(($0 + Int(seed)) & 0xFF) })
  }

  /// A tiny, dependency-free, guaranteed-valid 1x1 PNG, for tests that only need "some real image
  /// bytes" and don't want to spin up CoreGraphics. The literal is fixed, so the bytes never vary.
  public static let onePixelPNG: Data = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )!

  /// Builds a square `CGImage` whose pixels vary by position — pixel `(x, y)` is
  /// `RGBA(x, y, x + y, 255)` (truncated to a byte), mirroring platform-go's `BuildArbitraryImage`.
  /// Fully deterministic for a given size.
  public static func arbitraryImage(widthAndHeight: Int) -> CGImage {
    let size = max(1, widthAndHeight)
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * size
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * size)
    for y in 0..<size {
      for x in 0..<size {
        let offset = y * bytesPerRow + x * bytesPerPixel
        pixels[offset + 0] = UInt8(x & 0xFF)
        pixels[offset + 1] = UInt8(y & 0xFF)
        pixels[offset + 2] = UInt8((x + y) & 0xFF)
        pixels[offset + 3] = 0xFF
      }
    }
    let context = CGContext(
      data: &pixels,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
  }

  /// PNG-encodes ``arbitraryImage(widthAndHeight:)``, mirroring platform-go's
  /// `BuildArbitraryImagePNGBytes`. Returns valid PNG bytes any image loader can decode.
  public static func arbitraryImagePNGData(widthAndHeight: Int) -> Data {
    let image = arbitraryImage(widthAndHeight: widthAndHeight)
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else {
      fatalError("TestData: could not create a PNG image destination")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      fatalError("TestData: could not finalize the PNG image destination")
    }
    return data as Data
  }
}
