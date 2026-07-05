import Foundation

/// Compresses and decompresses byte buffers, ported from the `Compressor` interface in platform-go's
/// `compression/compressor.go`.
///
/// Go's interface is:
/// ```go
/// type Compressor interface {
///     CompressBytes(in []byte) ([]byte, error)
///     DecompressBytes(in []byte) ([]byte, error)
/// }
/// ```
/// The Swift port keeps the same two-method shape but swaps `[]byte` for `Data` and the Go
/// `(value, error)` return for idiomatic `throws` (all failures are ``CompressionError``). See
/// ``CompressionAlgorithm`` for why this port is *not* wire-compatible with the Go zstd/s2 output.
public protocol Compressor: Sendable {
  /// Compresses `data`, ported from Go's `CompressBytes`.
  /// - Throws: ``CompressionError/unsupportedAlgorithm(_:)`` for a recognized-but-unavailable
  ///   algorithm, or ``CompressionError/compressionFailed`` if the codec errors.
  func compress(_ data: Data) throws -> Data

  /// Decompresses `data`, ported from Go's `DecompressBytes`.
  /// - Throws: ``CompressionError/unsupportedAlgorithm(_:)`` for a recognized-but-unavailable
  ///   algorithm, ``CompressionError/decompressedTooLarge`` if the output would exceed the configured
  ///   cap, or ``CompressionError/decompressionFailed`` on corrupt input.
  func decompress(_ data: Data) throws -> Data
}

/// Builds a ``Compressor`` from a runtime algorithm name, ported from Go's
/// `NewCompressor(Algorithm(cfg.Algorithm))` config-string path.
///
/// - Parameters:
///   - name: the algorithm identifier (e.g. from a bundled config). Unrecognized names throw
///     ``CompressionError/invalidAlgorithm``, matching Go's `ErrInvalidAlgorithm`.
///   - maxDecompressedBytes: the decompression-bomb cap; a value `<= 0` keeps the default
///     (``AppleCompressor/defaultMaxDecompressedBytes``), mirroring Go's `WithMaxDecompressedBytes`.
/// - Returns: a configured ``Compressor``.
/// - Throws: ``CompressionError/invalidAlgorithm`` if `name` is not a known ``CompressionAlgorithm``.
///
/// Note that a *recognized* algorithm Apple cannot perform (``CompressionAlgorithm/zstd``/`s2`)
/// constructs successfully here (Go accepts them too) and only fails when you actually
/// compress/decompress — see ``CompressionError/unsupportedAlgorithm(_:)``.
public func makeCompressor(
  named name: String,
  maxDecompressedBytes: Int = AppleCompressor.defaultMaxDecompressedBytes
) throws -> Compressor {
  guard let algorithm = CompressionAlgorithm(rawValue: name) else {
    throw CompressionError.invalidAlgorithm
  }
  return AppleCompressor(algorithm: algorithm, maxDecompressedBytes: maxDecompressedBytes)
}
