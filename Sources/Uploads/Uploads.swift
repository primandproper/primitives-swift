/// # Uploads
///
/// Ported from platform-go's `uploads` package (`uploader.go`, `objectstorage/`, `images/`, `noop/`,
/// `mock/`, `config/`) — the client-relevant slice, per the iOS-only scope of this port (see
/// `PORTING.md`).
///
/// ## What the Go package does, and how this differs
///
/// Go's `uploads` exposes an ``Uploader``-shaped seam (`UploadManager`: `Save`/`Open`/`Delete`/`Exists`)
/// and, in the `objectstorage` subpackage, a single `Uploader` that fans out to **S3, GCS, Cloudflare
/// R2, Backblaze B2, the local filesystem, and an in-memory provider** via `gocloud.dev/blob` plus the
/// `aws-sdk-go-v2` stack. On iOS none of those cloud SDKs belong on the device: the settled port
/// architecture drops server/cloud backends and keeps the protocol seam so a native adapter can wrap it.
///
/// What travels over intact, and what changed:
///   * ``Uploader`` — the storage seam (``Uploader/save(_:data:options:)`` / ``Uploader/read(_:)`` /
///     ``Uploader/delete(_:)`` / ``Uploader/exists(_:)``), expressed over `Data` rather than Go's
///     `io.Reader`/`io.ReadCloser` (an iOS upload is a bounded in-memory blob, not a stream).
///   * ``FileManagerUploader`` — a **local** backend that saves/reads/deletes files under a sandbox
///     root via `FileManager`, the port of Go's `filesystem` provider (`gocloud fileblob`). It rejects
///     path-traversal (`..`) so a caller-supplied key can never escape the root — the analogue of the
///     0700 owner-only directory hardening Go's `bucket_filesystem.go` applies.
///   * ``PresignedUploader`` + ``URLSessionPresignedUploader`` — the **remote** seam, reshaped for iOS.
///     Rather than embedding an S3 client, the app PUTs/POSTs bytes to a **pre-signed URL** the server
///     mints (Go's `URLSigner.SignedURL`); the live impl performs that request with `URLSession`, shaped
///     so a native `URLSession` *background-upload* adapter (delegate + file-body, discretionary
///     scheduling) can wrap it later without reshaping callers.
///   * ``ImageThumbnailer`` — a thin thumbnail helper over ImageIO's
///     `CGImageSourceCreateThumbnailAtIndex`, the native analogue of Go's `images` subpackage
///     (`disintegration/imaging`), honoring EXIF orientation and never upscaling.
///   * ``NoopUploader`` / actor ``UploaderMock`` and ``NoopPresignedUploader`` / actor
///     ``PresignedUploaderMock`` — the no-op defaults and test doubles.
///   * ``UploadsConfig`` — the lenient-`Codable` config (Go's `env:` tags dropped per the settled
///     architecture; JSON keys preserved), embedding a ``CircuitBreaking/CircuitBreakerConfig`` for the
///     remote backend exactly as Go's `objectstorage.Config` does.
///
/// ## Dropped from Go
///
/// The S3/GCS/R2/Backblaze/in-memory `gocloud.dev/blob` providers and the entire `aws-sdk-go-v2`
/// dependency are **dropped**: no cloud SDK ships in the app. The `URLSigner`/`Attributer`/`Lister`/
/// `RangeReader` optional capabilities and the streaming `List` iterator are likewise dropped — a client
/// reads back only what it wrote — while the presigned-URL seam preserves the one signing use a device
/// actually needs (uploading its own bytes). Go's `samber/do` DI registration is replaced by plain
/// constructor injection.
public enum Uploads {}
