import Compression
import Foundation

/// A ``Compressor`` backed by Apple's built-in `Compression` framework, ported from the unexported
/// `compressor` struct in platform-go's `compression/compressor.go`.
///
/// Go's `compressor` streams through `klauspost/compress` writers/readers. This port streams through
/// the framework's `compression_stream` C API, which lets it enforce the decompression-bomb cap while
/// decoding (bounding output as it is produced, rather than trusting a declared size). The cap mirrors
/// Go's design exactly: zstd uses `WithDecoderMaxMemory`, S2 copies at most `cap+1` and treats the
/// extra byte as overflow — here we accumulate output and throw ``CompressionError/decompressedTooLarge``
/// the moment the running total exceeds the cap.
///
/// **Wire-format caveat:** the algorithms this struct can actually run (LZFSE/LZ4/LZMA/DEFLATE) are
/// *not* the algorithms the Go package uses (zstd/S2). Its output does not interoperate with the Go
/// service. See ``CompressionAlgorithm`` for the full explanation.
public struct AppleCompressor: Compressor {
  /// The selected algorithm.
  public let algorithm: CompressionAlgorithm

  /// Upper bound on bytes ``decompress(_:)`` will produce for a single input, guarding against
  /// decompression bombs. Mirrors Go's per-`compressor` `maxDecompressedBytes`.
  public let maxDecompressedBytes: Int

  /// Bounds how many bytes ``decompress(_:)`` will produce for a single input, guarding against
  /// decompression bombs (a small hostile payload that expands to gigabytes). Mirrors Go's
  /// `DefaultMaxDecompressedBytes` — 64 MiB, zstd's own default decoder memory limit.
  public static let defaultMaxDecompressedBytes = 64 << 20

  /// Size of the transient output buffer the streaming codec drains into, per `compression_stream`
  /// iteration. Not part of the wire format — purely a throughput knob.
  private static let streamingChunkSize = 64 << 10  // 64 KiB

  /// Creates a compressor for the given algorithm.
  /// - Parameters:
  ///   - algorithm: the algorithm to use.
  ///   - maxDecompressedBytes: the decompression-bomb cap; a value `<= 0` keeps
  ///     ``defaultMaxDecompressedBytes`` (mirroring Go's `WithMaxDecompressedBytes`, which ignores 0).
  public init(
    algorithm: CompressionAlgorithm,
    maxDecompressedBytes: Int = AppleCompressor.defaultMaxDecompressedBytes
  ) {
    self.algorithm = algorithm
    self.maxDecompressedBytes = maxDecompressedBytes > 0 ? maxDecompressedBytes : Self.defaultMaxDecompressedBytes
  }

  public func compress(_ data: Data) throws -> Data {
    guard let codec = algorithm.appleAlgorithm else {
      throw CompressionError.unsupportedAlgorithm(algorithm)
    }
    return try stream(operation: COMPRESSION_STREAM_ENCODE, codec: codec, input: data, cap: nil)
  }

  public func decompress(_ data: Data) throws -> Data {
    guard let codec = algorithm.appleAlgorithm else {
      throw CompressionError.unsupportedAlgorithm(algorithm)
    }
    return try stream(operation: COMPRESSION_STREAM_DECODE, codec: codec, input: data, cap: maxDecompressedBytes)
  }

  /// Runs the whole `input` through a one-shot `compression_stream` in the given direction.
  ///
  /// The entire input is handed to the stream up front with `COMPRESSION_STREAM_FINALIZE`; we then
  /// loop, draining the fixed output buffer, until the codec reports `END`. When `cap` is non-nil
  /// (the decompress path) the running output total is checked after every drained chunk so a bomb is
  /// rejected before its full size is ever allocated.
  private func stream(
    operation: compression_stream_operation,
    codec: compression_algorithm,
    input: Data,
    cap: Int?
  ) throws -> Data {
    let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.streamingChunkSize)
    defer { destination.deallocate() }

    // `compression_stream`'s pointer members are non-optional; seed them with `destination` as a
    // placeholder (both are overwritten before any read) so the struct can be constructed.
    var stream = compression_stream(
      dst_ptr: destination, dst_size: 0,
      src_ptr: UnsafePointer(destination), src_size: 0, state: nil)
    guard compression_stream_init(&stream, operation, codec) == COMPRESSION_STATUS_OK else {
      throw error(for: operation)
    }
    defer { compression_stream_destroy(&stream) }

    var output = Data()
    let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)

    let failure: CompressionError? = input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> CompressionError? in
      // For empty input `baseAddress` is nil; a valid non-null pointer with src_size 0 is required,
      // so borrow `destination` as a never-read placeholder.
      stream.src_ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) ?? UnsafePointer(destination)
      stream.src_size = raw.count

      while true {
        stream.dst_ptr = destination
        stream.dst_size = Self.streamingChunkSize
        let sourceRemainingBefore = stream.src_size

        let status = compression_stream_process(&stream, flags)
        switch status {
        case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
          let produced = Self.streamingChunkSize - stream.dst_size
          if produced > 0 {
            output.append(destination, count: produced)
            if let cap, output.count > cap {
              return .decompressedTooLarge
            }
          }
          // END means input is drained and all output flushed; OK means "call again" (buffer full or
          // more work pending), so keep looping.
          if status == COMPRESSION_STATUS_END {
            return nil
          }
          // Liveness guard: a healthy codec always makes progress on an OK status — it either produces
          // output or consumes input. If an iteration does *neither*, the `while true` would spin
          // forever. A corrupt/hostile stream (e.g. certain malformed DEFLATE) can provoke exactly this
          // stall, so treat a no-progress OK as a decode failure rather than hanging the caller.
          if produced == 0 && stream.src_size == sourceRemainingBefore {
            return error(for: operation)
          }
        default:  // COMPRESSION_STATUS_ERROR
          return error(for: operation)
        }
      }
    }

    if let failure {
      throw failure
    }
    return output
  }

  private func error(for operation: compression_stream_operation) -> CompressionError {
    operation == COMPRESSION_STREAM_ENCODE ? .compressionFailed : .decompressionFailed
  }
}
