import Foundation

/// Errors surfaced by the uploads seam.
///
/// platform-go returns wrapped `error` values plus the sentinels `ErrNilConfig` / `ErrUnknownProvider`
/// (objectstorage) and `ErrInvalidImageContentType` / `ErrInvalidThumbnailDimensions` / `ErrImageTooLarge`
/// (images). The Swift port names the concrete failure modes a client can branch on. ``pathEscapesRoot``
/// has no direct Go analogue — it is the typed form of the sandbox-root hardening this port makes explicit
/// (Go leaned on gocloud's own key validation plus 0700 directory modes).
public enum UploadsError: Error, Equatable, Sendable {
  /// A supplied path resolved outside the backend's sandbox root (e.g. contained `..` traversal). Carries
  /// the offending path. Rejected *before* any filesystem access.
  case pathEscapesRoot(String)
  /// A supplied path was empty or otherwise unusable as an object key. Carries the offending path.
  case invalidPath(String)
  /// No object exists at the requested path (read/attributes on a missing key).
  case notFound(String)
  /// The configured filesystem backend has no root directory (``FilesystemConfig/rootDirectory`` empty).
  case missingRootDirectory
  /// A presigned upload completed with a non-2xx status. Carries the status and a short message (the
  /// response body, truncated).
  case uploadFailed(status: Int, message: String)
  /// The circuit breaker guarding the remote backend is open; the request was refused without hitting the
  /// network. The client-side analogue of Go's `circuitbreaking.ErrCircuitBroken`.
  case circuitBroken
  /// The upload's HTTP round-trip produced a non-HTTP response (should not happen over `URLSession`).
  case nonHTTPResponse
  /// The bytes handed to ``ImageThumbnailer`` were not a decodable image. Go's `ErrInvalidImageContentType`.
  case unsupportedImageData
  /// A zero (or negative) thumbnail dimension was requested. Go's `ErrInvalidThumbnailDimensions`.
  case invalidThumbnailDimensions
  /// ImageIO failed to produce or encode the thumbnail. Carries a short reason.
  case thumbnailFailed(String)

  public var description: String {
    switch self {
    case .pathEscapesRoot(let path): return "path escapes storage root: \(path)"
    case .invalidPath(let path): return "invalid object path: \(path)"
    case .notFound(let path): return "object not found: \(path)"
    case .missingRootDirectory: return "filesystem backend requires a root directory"
    case .uploadFailed(let status, let message):
      return "presigned upload failed (\(status)): \(message)"
    case .circuitBroken: return "uploads circuit breaker open; refusing request"
    case .nonHTTPResponse: return "upload response was not an HTTP response"
    case .unsupportedImageData: return "unsupported or undecodable image data"
    case .invalidThumbnailDimensions: return "thumbnail dimensions must be greater than zero"
    case .thumbnailFailed(let reason): return "thumbnail generation failed: \(reason)"
    }
  }
}

extension UploadsError: LocalizedError {
  public var errorDescription: String? { description }
}
