import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Builds a solid-color PNG of `width`x`height` in memory, so a thumbnail test has a real, decodable image
/// without shipping a fixture file. Uses CoreGraphics + ImageIO, both available on macOS (where the tests
/// run) and iOS.
enum TestImage {
  static func png(width: Int, height: Int) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Fill with an off-gray so the encoder has real pixel content.
    context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!

    let out = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
      out as CFMutableData, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    _ = CGImageDestinationFinalize(destination)
    return out as Data
  }
}
