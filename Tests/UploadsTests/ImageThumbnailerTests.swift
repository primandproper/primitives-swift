import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Uploads

@Suite("ImageThumbnailer")
struct ImageThumbnailerTests {
  @Test("downscales a large image to fit the max pixel size, preserving format")
  func downscales() throws {
    let source = TestImage.png(width: 800, height: 400)
    let thumb = try ImageThumbnailer.thumbnail(from: source, maxPixelSize: 100)

    // Longest edge is capped at the requested size; aspect ratio preserved (800x400 -> 100x50).
    #expect(thumb.pixelWidth == 100)
    #expect(thumb.pixelHeight == 50)
    #expect(thumb.contentType == "image/png")

    // The output re-decodes as a real image at the reported dimensions.
    let reSource = try #require(CGImageSourceCreateWithData(thumb.data as CFData, nil))
    let reImage = try #require(CGImageSourceCreateImageAtIndex(reSource, 0, nil))
    #expect(reImage.width == 100)
    #expect(reImage.height == 50)
  }

  @Test("an image already within the cap is not upscaled")
  func neverUpscales() throws {
    let source = TestImage.png(width: 40, height: 40)
    let thumb = try ImageThumbnailer.thumbnail(from: source, maxPixelSize: 256)
    #expect(thumb.pixelWidth == 40)
    #expect(thumb.pixelHeight == 40)
  }

  @Test("a non-positive dimension throws invalidThumbnailDimensions")
  func zeroDimension() {
    let source = TestImage.png(width: 10, height: 10)
    #expect(throws: UploadsError.invalidThumbnailDimensions) {
      _ = try ImageThumbnailer.thumbnail(from: source, maxPixelSize: 0)
    }
  }

  @Test("undecodable bytes throw unsupportedImageData")
  func garbageData() {
    let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04])
    #expect(throws: UploadsError.unsupportedImageData) {
      _ = try ImageThumbnailer.thumbnail(from: garbage, maxPixelSize: 100)
    }
  }
}
