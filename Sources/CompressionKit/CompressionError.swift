import Foundation

/// Errors thrown by ``Compressor`` implementations, ported from the package-level `var` sentinels in
/// platform-go's `compression/compressor.go`.
///
/// Go exposes `ErrInvalidAlgorithm` and `ErrDecompressedTooLarge` as sentinel `error` values compared
/// with `errors.Is`. Swift folds them into a single typed enum (the same move ``EncryptionError``
/// makes) while preserving the exact Go messages in ``errorDescription`` so log/telemetry text lines up
/// across the two ports. ``unsupportedAlgorithm(_:)``, ``compressionFailed`` and
/// ``decompressionFailed`` are finer-grained cases with no direct Go sentinel: Go surfaced an
/// unsupported algorithm via a formatted error and a codec failure via the underlying reader/writer
/// error.
public enum CompressionError: Error, Equatable, Sendable {
  /// The requested algorithm name did not map to any known ``CompressionAlgorithm``.
  /// Mirrors Go's `ErrInvalidAlgorithm` ("invalid compression algorithm").
  case invalidAlgorithm

  /// The algorithm is a recognized ``CompressionAlgorithm`` but is not available on this platform —
  /// i.e. ``CompressionAlgorithm/zstd`` or ``CompressionAlgorithm/s2``, which Apple's `Compression`
  /// framework cannot perform. See ``CompressionAlgorithm`` for the full explanation of the gap.
  case unsupportedAlgorithm(CompressionAlgorithm)

  /// Decompressing the input would produce more than the configured maximum number of bytes — the
  /// decompression-bomb guard tripped. Mirrors Go's `ErrDecompressedTooLarge` ("decompressed output
  /// exceeds configured maximum").
  case decompressedTooLarge

  /// The `Compression` framework reported an error while compressing. Mirrors the underlying
  /// writer error Go returns from `enc.Close()`/`io.Copy`.
  case compressionFailed

  /// The `Compression` framework reported an error while decompressing (typically corrupt or
  /// truncated input). Mirrors the underlying reader error Go returns from `io.Copy`.
  case decompressionFailed
}

extension CompressionError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidAlgorithm:
      return "invalid compression algorithm"
    case .unsupportedAlgorithm(let algorithm):
      return "unsupported compression algorithm on this platform: \(algorithm.rawValue)"
    case .decompressedTooLarge:
      return "decompressed output exceeds configured maximum"
    case .compressionFailed:
      return "compression failed"
    case .decompressionFailed:
      return "decompression failed"
    }
  }
}
