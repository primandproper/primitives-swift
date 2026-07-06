import Foundation

/// String identifier generation, ported from platform-go's `identifiers` package.
///
/// Go delegates to `github.com/rs/xid`, whose IDs are **not** UUIDs: an xid is a 12-byte value
/// (4-byte seconds timestamp, 3-byte machine ID, 2-byte process ID, 3-byte monotonic counter)
/// rendered as a 20-character, lexically-sortable, lowercase base32-hex string over the alphabet
/// `0123456789abcdefghijklmnopqrstuv`. We reproduce that scheme byte-for-byte rather than mapping
/// to Foundation's `UUID`, because the whole point of these IDs is that a Go service using `xid`
/// can round-trip and validate the strings we mint — a `UUID` would be wire-incompatible.
///
/// The one intentional divergence is the machine ID: xid hashes the host's machine-id/hostname;
/// we derive three bytes from the host name (via `gethostname(2)`) and fall back to random bytes.
/// The exact machine-ID value never affects validity (any three bytes are legal), so this stays
/// format-faithful while remaining dependency-free on Apple platforms.
public enum Identifier {
  /// Produces a new 20-character xid string. Mirrors Go's `identifiers.New()`.
  public static func new() -> String {
    XIDGenerator.shared.newIDString()
  }

  /// Reports whether `id` is a syntactically valid xid string (length, alphabet, and the canonical
  /// last-character constraint xid enforces on decode). This is the `Bool`-returning form; prefer it
  /// for control flow.
  public static func isValid(_ id: String) -> Bool {
    XIDGenerator.isValidIDString(id)
  }

  /// Throwing counterpart mirroring Go's `identifiers.Validate`, which returns an `error`. Throws
  /// ``InvalidIdentifierError`` when `id` is not a valid xid string.
  public static func validate(_ id: String) throws {
    guard isValid(id) else { throw InvalidIdentifierError(value: id) }
  }
}

/// Error thrown by ``Identifier/validate(_:)`` for a malformed identifier. Mirrors xid's
/// `ErrInvalidID`, but carries the offending value for better diagnostics.
public struct InvalidIdentifierError: Error, Equatable, Sendable {
  public let value: String
  public init(value: String) { self.value = value }
}
