import Foundation
import Testing

@testable import CompressionKit

/// The algorithms Apple's `Compression` framework can actually run — everything except the
/// recognized-but-unsupported ``CompressionAlgorithm/zstd``/``CompressionAlgorithm/s2``.
private let supportedAlgorithms: [CompressionAlgorithm] = [.lzfse, .lz4, .lzma, .zlib]

@Suite("Apple-backed Compressor round-trips")
struct CompressorRoundTripTests {
  @Test("compress then decompress returns the original", arguments: supportedAlgorithms)
  func roundTrip(algorithm: CompressionAlgorithm) throws {
    let compressor = AppleCompressor(algorithm: algorithm)
    let original = Data("the quick brown fox jumps over the lazy dog".utf8)

    let compressed = try compressor.compress(original)
    #expect(!compressed.isEmpty)

    let restored = try compressor.decompress(compressed)
    #expect(restored == original)
  }

  @Test("round-trips a Unicode / JSON-ish payload", arguments: supportedAlgorithms)
  func unicodeRoundTrip(algorithm: CompressionAlgorithm) throws {
    let compressor = AppleCompressor(algorithm: algorithm)
    // Mirrors the `whatever{Name:"testing"}` JSON the Go compressor_test.go compresses.
    let original = Data(#"{"name":"héllo • 世界 • 🔐"}"#.utf8)

    #expect(try compressor.decompress(compressor.compress(original)) == original)
  }

  @Test("round-trips the empty payload", arguments: supportedAlgorithms)
  func emptyRoundTrip(algorithm: CompressionAlgorithm) throws {
    let compressor = AppleCompressor(algorithm: algorithm)
    #expect(try compressor.decompress(compressor.compress(Data())) == Data())
  }

  @Test("actually shrinks a highly compressible payload", arguments: supportedAlgorithms)
  func shrinksCompressibleData(algorithm: CompressionAlgorithm) throws {
    let compressor = AppleCompressor(algorithm: algorithm)
    // 20 KiB of a repeating phrase — mirrors the Go benchmark's `strings.Repeat(..., 512)`.
    let original = Data(String(repeating: "the quick brown fox ", count: 1024).utf8)

    let compressed = try compressor.compress(original)
    #expect(compressed.count < original.count)
    #expect(try compressor.decompress(compressed) == original)
  }
}

@Suite("Unsupported algorithms (the Go zstd/S2 wire-format gap)")
struct UnsupportedAlgorithmTests {
  /// A real zstd payload produced by the Go `Test_compressor_CompressBytes/zstandard` case
  /// (`comp.CompressBytes(encoder.MustEncodeJSON(ctx, whatever{Name:"testing"}))`), URL-safe base64.
  /// We keep it to document — with actual Go output — that Apple's framework cannot decode it.
  private let goZstdVector = "KLUv_QQAmQAAeyJuYW1lIjoidGVzdGluZyJ9Ch6HXww="

  /// The equivalent real S2 payload from the Go `Test_compressor_CompressBytes/s2` case.
  private let goS2Vector = "_wYAAFMyc1R3TwEXAABui7jXeyJuYW1lIjoidGVzdGluZyJ9Cg=="

  @Test("zstd is recognized but throws unsupported on compress and decompress")
  func zstdUnsupported() throws {
    let compressor = AppleCompressor(algorithm: .zstd)
    #expect(throws: CompressionError.unsupportedAlgorithm(.zstd)) {
      _ = try compressor.compress(Data("testing".utf8))
    }

    let goBytes = try #require(urlSafeBase64Decode(goZstdVector))
    #expect(throws: CompressionError.unsupportedAlgorithm(.zstd)) {
      _ = try compressor.decompress(goBytes)
    }
  }

  @Test("s2 is recognized but throws unsupported on compress and decompress")
  func s2Unsupported() throws {
    let compressor = AppleCompressor(algorithm: .s2)
    #expect(throws: CompressionError.unsupportedAlgorithm(.s2)) {
      _ = try compressor.compress(Data("testing".utf8))
    }

    let goBytes = try #require(urlSafeBase64Decode(goS2Vector))
    #expect(throws: CompressionError.unsupportedAlgorithm(.s2)) {
      _ = try compressor.decompress(goBytes)
    }
  }

  private func urlSafeBase64Decode(_ string: String) -> Data? {
    let standard =
      string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    return Data(base64Encoded: standard)
  }
}

@Suite("Factory / config-string construction")
struct MakeCompressorTests {
  @Test("maps every known algorithm name", arguments: CompressionAlgorithm.allCases)
  func knownNames(algorithm: CompressionAlgorithm) throws {
    let compressor = try #require(makeCompressor(named: algorithm.rawValue) as? AppleCompressor)
    #expect(compressor.algorithm == algorithm)
  }

  @Test("rejects an unknown algorithm name")
  func unknownName() {
    // Mirrors Go's `NewCompressor(Algorithm(t.Name()))` returning ErrInvalidAlgorithm.
    #expect(throws: CompressionError.invalidAlgorithm) {
      _ = try makeCompressor(named: "definitely-not-an-algorithm")
    }
  }

  @Test("carries a custom cap through the factory")
  func customCap() throws {
    let compressor = try #require(
      makeCompressor(named: "lzfse", maxDecompressedBytes: 4096) as? AppleCompressor)
    #expect(compressor.maxDecompressedBytes == 4096)
  }
}

@Suite("Decompression-bomb guard")
struct DecompressionBombTests {
  @Test("rejects output larger than the cap", arguments: supportedAlgorithms)
  func rejectsOversizedOutput(algorithm: CompressionAlgorithm) throws {
    let maxOut = 4 << 10  // 4 KiB, matching the Go bomb test.
    // 1 MiB of zeros compresses to a tiny payload but expands past the cap.
    let bomb = Data(count: 1 << 20)

    let packer = AppleCompressor(algorithm: algorithm)
    let compressed = try packer.compress(bomb)
    // The point of a bomb: a tiny payload expands enormously. Apple's LZ4 frames in ~64 KiB blocks,
    // so use a generous bound (still ~16x under the 1 MiB decompressed size) rather than a tight one.
    #expect(compressed.count < 64 << 10)

    let capped = AppleCompressor(algorithm: algorithm, maxDecompressedBytes: maxOut)
    #expect(throws: CompressionError.decompressedTooLarge) {
      _ = try capped.decompress(compressed)
    }
  }

  @Test("allows output within the cap", arguments: supportedAlgorithms)
  func allowsWithinCap(algorithm: CompressionAlgorithm) throws {
    let payload = Data("a modest payload well under the configured cap".utf8)

    let packer = AppleCompressor(algorithm: algorithm)
    let compressed = try packer.compress(payload)

    let capped = AppleCompressor(algorithm: algorithm, maxDecompressedBytes: 1 << 20)
    #expect(try capped.decompress(compressed) == payload)
  }

  @Test("default cap is 64 MiB")
  func defaultCap() {
    #expect(AppleCompressor(algorithm: .lzfse).maxDecompressedBytes == 64 << 20)
    // A non-positive override keeps the default, mirroring Go's WithMaxDecompressedBytes(0).
    #expect(
      AppleCompressor(algorithm: .lzfse, maxDecompressedBytes: 0).maxDecompressedBytes == 64 << 20)
    #expect(
      AppleCompressor(algorithm: .lzfse, maxDecompressedBytes: -5).maxDecompressedBytes == 64 << 20)
  }
}

@Suite("Corrupt input")
struct CorruptInputTests {
  @Test("decompressing truncated data throws", arguments: supportedAlgorithms)
  func truncatedFrame(algorithm: CompressionAlgorithm) throws {
    let compressor = AppleCompressor(algorithm: algorithm)
    let original = Data(String(repeating: "compress me please ", count: 1000).utf8)

    let compressed = try compressor.compress(original)
    // Chop the frame in half so it can never finalize.
    let truncated = compressed.prefix(compressed.count / 2)

    #expect(throws: CompressionError.decompressionFailed) {
      _ = try compressor.decompress(Data(truncated))
    }
  }

  @Test("decompressing clearly-invalid LZFSE data throws")
  func garbageLZFSE() {
    // LZFSE frames start with a magic header; arbitrary ASCII is rejected outright.
    let compressor = AppleCompressor(algorithm: .lzfse)
    #expect(throws: CompressionError.decompressionFailed) {
      _ = try compressor.decompress(Data("not valid lzfse data at all".utf8))
    }
  }
}
