import Foundation

/// Uploads object bytes to a server-minted **pre-signed URL** — the remote storage seam, shaped for a
/// native `URLSession` *background upload* adapter to wrap.
///
/// This is the port's reshaping of Go's cloud-backed `objectstorage.Uploader.Save`. On iOS the device
/// must never hold cloud credentials or an S3 SDK, so the service signs a short-lived URL (Go's
/// `URLSigner.SignedURL`) and the app simply PUTs/POSTs its bytes there. Keeping this a one-method
/// protocol over ``PresignedUploadRequest`` means the default live impl
/// (``URLSessionPresignedUploader``, a foreground `URLSession.upload`) and a future background adapter
/// (a delegate-driven `URLSession` with a `background` configuration and a file body, so uploads survive
/// app suspension) are interchangeable behind the same call site.
///
/// Conformers: ``URLSessionPresignedUploader`` (live), ``NoopPresignedUploader`` (safe default), and
/// actor ``PresignedUploaderMock`` (test double).
public protocol PresignedUploader: Sendable {
  /// Performs `request`, returning the store's ``PresignedUploadResponse`` on a 2xx. Throws
  /// ``UploadsError/uploadFailed(status:message:)`` for a non-2xx, ``UploadsError/circuitBroken`` when the
  /// breaker is open, or a transport error.
  @discardableResult
  func upload(_ request: PresignedUploadRequest) async throws -> PresignedUploadResponse
}
