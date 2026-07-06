import Foundation

/// The HTTP method a presigned upload uses. A pre-signed URL is minted for one verb: S3-style stores
/// sign a **PUT** of the object bytes, while browser/form-style flows sign a **POST**. Empty/other verbs
/// aren't meaningful for a byte upload, so the seam constrains the choice to these two.
public enum PresignedUploadMethod: String, Sendable, Equatable {
  case put = "PUT"
  case post = "POST"
}

/// A single presigned upload: the pre-signed `url` the server minted, the `method` it was signed for,
/// the object `body`, and the optional stored-metadata headers.
///
/// This is the client analogue of Go's `URLSigner.SignedURL(path, {Method: "PUT", ContentType})` followed
/// by the caller PUTting bytes: the *server* signs the URL (embedding the bucket/key and an expiry), and
/// the device only ever sees this opaque URL plus the bytes to send. Keeping the seam a value struct lets
/// a native background-upload adapter consume the exact same request shape as the default live impl.
public struct PresignedUploadRequest: Sendable, Equatable {
  /// The pre-signed URL to upload to.
  public var url: URL
  /// The HTTP verb the URL was signed for. Defaults to ``PresignedUploadMethod/put``.
  public var method: PresignedUploadMethod
  /// The object bytes to upload.
  public var body: Data
  /// The `Content-Type` to send. For a PUT-signed URL this must match what the URL was signed with, or the
  /// store rejects the request; empty omits the header.
  public var contentType: String?
  /// The `Cache-Control` to store with the object; empty omits the header.
  public var cacheControl: String?
  /// Any additional headers to send verbatim (e.g. `x-amz-*` metadata the URL was signed to require).
  public var extraHeaders: [String: String]

  public init(
    url: URL,
    method: PresignedUploadMethod = .put,
    body: Data,
    contentType: String? = nil,
    cacheControl: String? = nil,
    extraHeaders: [String: String] = [:]
  ) {
    self.url = url
    self.method = method
    self.body = body
    self.contentType = contentType
    self.cacheControl = cacheControl
    self.extraHeaders = extraHeaders
  }

  /// Builds the request from a ``SaveOptions`` bag, so a caller that already resolved options for the local
  /// backend can reuse them for a remote upload without re-plucking fields. Empty option strings become
  /// `nil` (header omitted).
  public init(
    url: URL,
    method: PresignedUploadMethod = .put,
    body: Data,
    options: SaveOptions,
    extraHeaders: [String: String] = [:]
  ) {
    self.init(
      url: url,
      method: method,
      body: body,
      contentType: options.contentType.isEmpty ? nil : options.contentType,
      cacheControl: options.cacheControl.isEmpty ? nil : options.cacheControl,
      extraHeaders: extraHeaders)
  }
}

/// The outcome of a successful presigned upload: the store's `statusCode`, the `etag` it assigned (when
/// present — S3/R2/B2 return one, letting the app record the stored version), and the response headers.
public struct PresignedUploadResponse: Sendable, Equatable {
  /// The 2xx status the store returned.
  public var statusCode: Int
  /// The object's `ETag` header, unquoted, when the store supplied one.
  public var etag: String?
  /// The full response header set, keyed as returned.
  public var headers: [String: String]

  public init(statusCode: Int, etag: String? = nil, headers: [String: String] = [:]) {
    self.statusCode = statusCode
    self.etag = etag
    self.headers = headers
  }
}
