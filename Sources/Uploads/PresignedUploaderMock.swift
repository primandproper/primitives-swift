import Foundation

/// A test double for ``PresignedUploader``. An `actor` (thread safety without hand-rolled locks) that
/// records each ``upload(_:)`` request and returns either a scripted handler's result or a default `200`.
///
/// `uploadHandler` is a `public var` on an actor, so it can't be assigned cross-actor under Swift 6; use
/// ``setUploadHandler(_:)`` to script the double after construction (REPO-05).
public actor PresignedUploaderMock: PresignedUploader {
  public var uploadHandler:
    (@Sendable (PresignedUploadRequest) async throws -> PresignedUploadResponse)?

  public private(set) var uploadCalls: [PresignedUploadRequest] = []

  public init(
    uploadHandler: (
      @Sendable (PresignedUploadRequest) async throws -> PresignedUploadResponse
    )? = nil
  ) {
    self.uploadHandler = uploadHandler
  }

  public func setUploadHandler(
    _ handler: (@Sendable (PresignedUploadRequest) async throws -> PresignedUploadResponse)?
  ) {
    uploadHandler = handler
  }

  @discardableResult
  public func upload(_ request: PresignedUploadRequest) async throws -> PresignedUploadResponse {
    uploadCalls.append(request)
    if let uploadHandler {
      return try await uploadHandler(request)
    }
    return PresignedUploadResponse(statusCode: 200)
  }
}
