import Foundation
import Testing

@testable import CompressionKit

/// The algorithms Apple's `Compression` framework can actually run.
private let apple: [CompressionAlgorithm] = [.lzfse, .lz4, .lzma, .zlib]

/// REPO-10: decompressing garbage and empty input must **terminate** (error or return) for every
/// Apple-backed algorithm — never hang.
///
/// `AppleCompressor.stream` loops `while true` on the `compression_stream` C API, draining output until
/// the codec reports `END`. A corrupt stream that leaves the codec reporting `OK` while consuming no
/// input and producing no output would spin that loop forever. The fix is the liveness guard in
/// `stream` (a no-progress `OK` is treated as a decode failure); these tests are the regression that
/// pins it — each call is expected to return quickly, so a reintroduced hang shows up as a stuck test.
@Suite("CompressionKit — garbage / empty decompress terminates (REPO-10)")
struct CompressionRobustnessTests {
  /// A spread of hostile inputs: short, long, structured, and high-entropy.
  private func garbagePayloads() -> [Data] {
    [
      Data("not valid compressed data at all, absolutely not".utf8),
      Data([0x00]),
      Data([0xFF, 0xFF, 0xFF, 0xFF]),
      Data(repeating: 0xAB, count: 4096),
      Data((0..<512).map { UInt8($0 & 0xFF) }),
      Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00]),  // gzip-ish magic then nonsense
    ]
  }

  @Test("garbage input errors (never hangs)", arguments: apple)
  func garbageTerminates(algorithm: CompressionAlgorithm) throws {
    let compressor = AppleCompressor(algorithm: algorithm)
    for payload in garbagePayloads() {
      // Some byte sequences are coincidentally a valid frame for a given codec; the contract we assert
      // is *termination*. If it decodes, fine; if not, it must surface a CompressionError —
      // crucially, the call must return rather than spin forever.
      do {
        _ = try compressor.decompress(payload)
      } catch let error as CompressionError {
        #expect(error == .decompressionFailed || error == .decompressedTooLarge)
      }
    }
  }

  @Test("empty input decompresses to empty or errors — but terminates", arguments: apple)
  func emptyTerminates(algorithm: CompressionAlgorithm) throws {
    let compressor = AppleCompressor(algorithm: algorithm)
    // The call must complete. Either outcome is acceptable; a hang is not.
    if let output = try? compressor.decompress(Data()) {
      #expect(output.isEmpty)
    }
  }

  @Test("a tiny cap plus garbage still terminates (guard interplay)", arguments: apple)
  func cappedGarbageTerminates(algorithm: CompressionAlgorithm) throws {
    let capped = AppleCompressor(algorithm: algorithm, maxDecompressedBytes: 16)
    for payload in garbagePayloads() {
      do {
        _ = try capped.decompress(payload)
      } catch is CompressionError {
        // expected for most garbage; the point is it returns.
      }
    }
  }
}
