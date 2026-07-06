import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A generated thumbnail: the re-encoded bytes, its pixel dimensions, and its content type.
public struct Thumbnail: Sendable, Equatable {
  /// The re-encoded thumbnail bytes.
  public var data: Data
  /// The thumbnail's width in pixels.
  public var pixelWidth: Int
  /// The thumbnail's height in pixels.
  public var pixelHeight: Int
  /// The MIME content type of ``data`` (e.g. `image/png`), preserved from the source when possible.
  public var contentType: String

  public init(data: Data, pixelWidth: Int, pixelHeight: Int, contentType: String) {
    self.data = data
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.contentType = contentType
  }
}

/// A thin image-thumbnail helper over ImageIO's `CGImageSourceCreateThumbnailAtIndex`, the native
/// analogue of platform-go's `uploads/images` subpackage (`disintegration/imaging`).
///
/// **Why ImageIO, not a hand-rolled resize.** `CGImageSourceCreateThumbnailAtIndex` decodes *directly* at
/// the target size rather than decoding the full image and downscaling, so a 4000×3000 photo never
/// materializes as a ~48 MB pixel buffer just to make a 256px thumbnail — the same
/// don't-allocate-the-giant-image concern Go guards with its `maxImageDimension` check, handled here by the
/// framework. `kCGImageSourceCreateThumbnailWithTransform` bakes in the EXIF orientation so a
/// portrait phone photo comes out upright (Go used `imaging.AutoOrientation(true)`), and passing
/// `…FromImageIfAbsent` (not `…Always`) means an image already smaller than the cap is returned as-is
/// rather than upscaled — matching Go's "never upscale" `thumbnail` behavior.
public enum ImageThumbnailer {
  /// Generates a thumbnail of `data` that fits within `maxPixelSize` on its longest edge, re-encoded in the
  /// source's format (PNG/JPEG/HEIC/…). Aspect ratio is preserved and the image is never upscaled.
  ///
  /// - Throws: ``UploadsError/invalidThumbnailDimensions`` for a non-positive `maxPixelSize`,
  ///   ``UploadsError/unsupportedImageData`` when `data` is not a decodable image, and
  ///   ``UploadsError/thumbnailFailed(_:)`` when ImageIO can't produce or encode the result.
  public static func thumbnail(from data: Data, maxPixelSize: Int) throws -> Thumbnail {
    guard maxPixelSize > 0 else {
      throw UploadsError.invalidThumbnailDimensions
    }

    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      throw UploadsError.unsupportedImageData
    }
    // A source that yields no image (0 frames) or whose type can't be sniffed is not a usable image.
    guard CGImageSourceGetCount(source) > 0, let sourceType = CGImageSourceGetType(source) else {
      throw UploadsError.unsupportedImageData
    }

    let options: [CFString: Any] = [
      // IfAbsent (not Always) so an image already within the cap is returned at its native size — never
      // upscaled, matching Go's `thumbnail` which returns small images unchanged.
      kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
      // Honor the EXIF orientation tag so portrait photos come out upright.
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]

    guard
      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else {
      throw UploadsError.thumbnailFailed("ImageIO could not create a thumbnail")
    }

    let encoded = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        encoded as CFMutableData, sourceType, 1, nil)
    else {
      throw UploadsError.thumbnailFailed("ImageIO could not create an image destination")
    }
    CGImageDestinationAddImage(destination, thumbnail, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw UploadsError.thumbnailFailed("ImageIO could not finalize the thumbnail")
    }

    return Thumbnail(
      data: encoded as Data,
      pixelWidth: thumbnail.width,
      pixelHeight: thumbnail.height,
      contentType: contentType(for: sourceType))
  }

  /// Maps an ImageIO UTI (e.g. `public.png`) to its MIME type, falling back to the raw UTI string.
  private static func contentType(for uti: CFString) -> String {
    let identifier = uti as String
    if let type = UTType(identifier), let mime = type.preferredMIMEType {
      return mime
    }
    return identifier
  }
}
