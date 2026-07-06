import Foundation

/// A no-op ``PresignedUploader``. The safe default when no remote backend is configured: every upload
/// "succeeds" with a synthetic `200` and no ETag, sending nothing over the network — the presigned-seam
/// analogue of ``NoopUploader``.
public struct NoopPresignedUploader: PresignedUploader {
  public init() {}

  @discardableResult
  public func upload(_ request: PresignedUploadRequest) async throws -> PresignedUploadResponse {
    PresignedUploadResponse(statusCode: 200)
  }
}
