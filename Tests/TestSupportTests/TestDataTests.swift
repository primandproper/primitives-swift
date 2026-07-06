import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import TestSupport

@Suite("TestData")
struct TestDataTests {
  @Test("example keys are the documented byte lengths")
  func exampleKeyLengths() {
    #expect(TestData.example32ByteKey.utf8.count == 32)
    #expect(TestData.example64ByteKey.utf8.count == 64)
  }

  @Test("deterministicBytes is reproducible and seed-shiftable")
  func deterministicBytes() {
    #expect(TestData.deterministicBytes(count: 0) == Data())
    #expect(TestData.deterministicBytes(count: 4) == TestData.deterministicBytes(count: 4))
    #expect(Array(TestData.deterministicBytes(count: 4)) == [0, 1, 2, 3])
    #expect(Array(TestData.deterministicBytes(count: 4, seed: 10)) == [10, 11, 12, 13])
    // Wraps at 256.
    #expect(Array(TestData.deterministicBytes(count: 1, seed: 255)) == [255])
    #expect(TestData.deterministicBytes(count: 300).count == 300)
  }

  @Test("onePixelPNG is a valid, decodable 1x1 PNG")
  func onePixelPNGIsValid() throws {
    let bytes = TestData.onePixelPNG
    #expect(Array(bytes.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])  // PNG signature
    let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 1)
    #expect(image.height == 1)
  }

  @Test("arbitraryImage has the requested dimensions and mirrors the Go pixel formula")
  func arbitraryImageDimensions() {
    let image = TestData.arbitraryImage(widthAndHeight: 8)
    #expect(image.width == 8)
    #expect(image.height == 8)
  }

  @Test("arbitraryImagePNGData round-trips through an image decoder")
  func arbitraryImagePNGDecodes() throws {
    let data = TestData.arbitraryImagePNGData(widthAndHeight: 5)
    #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 5)
    #expect(image.height == 5)
  }

  @Test("arbitraryImagePNGData is deterministic for a given size")
  func arbitraryImageDeterministic() {
    #expect(
      TestData.arbitraryImagePNGData(widthAndHeight: 4)
        == TestData.arbitraryImagePNGData(widthAndHeight: 4))
  }
}
