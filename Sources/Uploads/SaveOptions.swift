/// The resolved settings for a save, ported from platform-go's `uploads.SaveOptions`.
///
/// Go exposes these through functional options (`WithContentType`, `WithCacheControl`) resolved by
/// `BuildSaveOptions`; Swift's default-argument ergonomics make a plain value struct clearer, so the
/// port carries the two fields directly. Both default to empty, mirroring Go's zero value.
///
/// **Where each field is honored.** ``contentType`` and ``cacheControl`` are metadata a *remote* object
/// store persists and serves back as headers; the presigned-upload seam (``PresignedUploadRequest``)
/// forwards them as `Content-Type` / `Cache-Control` on the wire. The local ``FileManagerUploader``
/// stores raw bytes and has nowhere to persist per-object HTTP metadata — a filesystem has no header
/// sidecar in this port — so it accepts these options for a uniform call site but does not retain them,
/// exactly as reading a bare file back gives you no stored content type.
public struct SaveOptions: Sendable, Equatable {
  /// The stored `Content-Type`. Empty leaves it unset (a remote store may sniff it from the bytes).
  public var contentType: String
  /// The stored `Cache-Control` header for served objects. Empty leaves it unset.
  public var cacheControl: String

  public init(contentType: String = "", cacheControl: String = "") {
    self.contentType = contentType
    self.cacheControl = cacheControl
  }
}
