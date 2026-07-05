import Compression
import Foundation

/// A selectable compression algorithm, ported from the `AlgorithmZstd`/`AlgorithmS2` string constants
/// and the `Algorithm string` type in platform-go's `compression/compressor.go`.
///
/// # The hard wire-format gap
///
/// The Go package compresses with **Zstandard** (`klauspost/compress/zstd`) and **S2**
/// (`klauspost/compress/s2`, a Snappy-framed variant). **Apple's built-in `Compression` framework
/// implements neither.** Its `compression_algorithm` set is `lzfse`, `lz4`, `lzma`, and `zlib`
/// (raw DEFLATE) — there is no zstd and no snappy/s2. So, unlike ``Cryptography`` (where CryptoKit's
/// AES-GCM matches Go's wire format byte-for-byte), this port **cannot** produce or consume payloads
/// that interoperate with the Go service without pulling in an external SPM dependency (e.g. a
/// vendored libzstd), which this module deliberately avoids.
///
/// The port therefore does two honest things, mirroring how ``EncryptionProvider`` keeps `salsa20`:
///   * ``zstd`` and ``s2`` are **kept as recognized cases** so a Go-authored config string still
///     decodes — but selecting them throws ``CompressionError/unsupportedAlgorithm(_:)`` at
///     compress/decompress time. They are *not* silently remapped onto a different algorithm; a
///     caller is never handed lzfse bytes while believing they hold zstd.
///   * The four **Apple-native** algorithms are exposed and fully implemented (see ``AppleCompressor``).
///     They round-trip correctly within the Apple platform but are **not** wire-compatible with the
///     Go zstd/s2 payloads.
///
/// If a real flow needs to exchange compressed bytes with the Go side, wire up a zstd library and add
/// a backing that maps ``zstd`` to it; this enum's shape leaves that seam open.
public enum CompressionAlgorithm: String, Codable, Sendable, CaseIterable {
  /// Zstandard. **Recognized for config compatibility with platform-go but unsupported here** —
  /// Apple's `Compression` framework has no zstd codec. Selecting it throws
  /// ``CompressionError/unsupportedAlgorithm(_:)``. Mirrors Go's `AlgorithmZstd`.
  case zstd

  /// S2 (Snappy-framed). **Recognized for config compatibility with platform-go but unsupported
  /// here** — Apple's `Compression` framework has no Snappy/S2 codec. Selecting it throws
  /// ``CompressionError/unsupportedAlgorithm(_:)``. Mirrors Go's `AlgorithmS2`.
  case s2

  /// LZFSE — Apple's own algorithm, the best speed/ratio balance on Apple silicon. Fully supported.
  /// No platform-go analogue; not interoperable with the Go service.
  case lzfse

  /// LZ4 — very fast, lower ratio. Fully supported. No platform-go analogue.
  case lz4

  /// LZMA — high ratio, slower. Fully supported. No platform-go analogue.
  case lzma

  /// Raw DEFLATE (RFC 1951), Apple's `COMPRESSION_ZLIB`. Fully supported. **Note:** this is the bare
  /// DEFLATE bitstream — it carries *neither* a zlib wrapper (RFC 1950) *nor* a gzip header/trailer
  /// (RFC 1952), so it does not interoperate with Go's `gzip`/`zlib` writers either. No platform-go
  /// analogue in this package.
  case zlib

  /// The Apple `Compression` framework codec backing this algorithm, or `nil` for the algorithms
  /// Apple cannot perform (``zstd``/``s2``).
  var appleAlgorithm: compression_algorithm? {
    switch self {
    case .zstd, .s2:
      return nil
    case .lzfse:
      return COMPRESSION_LZFSE
    case .lz4:
      return COMPRESSION_LZ4
    case .lzma:
      return COMPRESSION_LZMA
    case .zlib:
      return COMPRESSION_ZLIB
    }
  }
}
