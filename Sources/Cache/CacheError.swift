/// A cache failure, ported loosely from platform-go's `cache.ErrNotFound` sentinel plus the disk/IO and
/// codec errors this port introduces.
///
/// Go's only exported cache error is the `ErrNotFound` sentinel (a miss). The in-memory port never
/// throws — a miss is `nil` — but the disk provider can fail on FileManager IO or on encode/decode, so
/// those concrete modes are named here. Each carries a `String` rendering of the underlying error so the
/// enum stays `Equatable` (Foundation's `Error` values are not).
public enum CacheError: Error, Equatable {
  /// The Go `ErrNotFound` sentinel. The seam returns `nil` for a miss and never throws this; it exists
  /// for callers that prefer a throwing "not found" and for parity with the Go surface.
  case notFound
  /// A FileManager read/write/create failed on the disk provider. The associated value is the
  /// underlying error's description.
  case io(String)
  /// Encoding a value to bytes failed (disk provider). The associated value is the codec error's
  /// description.
  case encoding(String)
  /// Decoding bytes back into a value failed (disk provider). The associated value is the codec error's
  /// description.
  case decoding(String)
  /// ``CacheConfig/makeCache(pillars:encoder:)`` was asked for a provider it doesn't recognize — the
  /// analogue of Go's `errors.Newf("invalid cache provider: %q", cfg.Provider)`. Redis resolves here
  /// until a remote adapter is wired.
  case invalidProvider(String)
}
