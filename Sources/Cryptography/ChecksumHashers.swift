import Foundation

// These three hashers are ported from platform-go's `cryptography/hashing/{adler32,crc64,fnv}`.
//
// Unlike SHA-256/512, none of these has a CryptoKit (or Foundation) equivalent, so each is
// implemented by hand to reproduce Go's stdlib output *exactly* — the packages exist to detect
// accidental corruption and to key hash tables, and their hex output is a format contract that must
// match the Go origin byte-for-byte. Every implementation here is validated against the same
// known-answer vectors the Go `_test.go` files use.
//
// WARNING (carried over verbatim from the Go package docs): these are NON-CRYPTOGRAPHIC checksums.
// They provide NO security guarantees and MUST NOT be used for password hashing, digital signatures,
// tamper resistance, or any security-sensitive purpose. Use ``SHA256Hasher`` / ``SHA512Hasher`` there.

/// A ``ContentHasher`` backed by the Adler-32 checksum (Go `hash/adler32`).
///
/// - Warning: non-cryptographic. See the file-level note.
public struct Adler32Hasher: ContentHasher {
  public init() {}

  public func hash(_ content: String) -> String {
    let mod: UInt32 = 65521
    var a: UInt32 = 1  // Go's adler32.New() seeds the digest to 1.
    var b: UInt32 = 0
    for byte in content.utf8 {
      a = (a &+ UInt32(byte)) % mod
      b = (b &+ a) % mod
    }
    let sum = (b << 16) | a
    return HexEncoding.encode(bigEndianBytes(sum))
  }
}

/// A ``ContentHasher`` backed by the CRC-64 (ISO polynomial) checksum (Go `hash/crc64` with `crc64.ISO`).
///
/// Reproduces Go's reflected, table-driven CRC-64 update (`crc = ^0` start, `~crc` finish) so the
/// 8-byte big-endian digest matches `crc64.MakeTable(crc64.ISO)`.
///
/// - Warning: non-cryptographic. See the file-level note.
public struct CRC64Hasher: ContentHasher {
  public init() {}

  /// Go's `crc64.ISO` polynomial (reversed representation).
  private static let iso: UInt64 = 0xD800_0000_0000_0000

  /// Precomputed table, matching Go's `makeTable`.
  private static let table: [UInt64] = {
    var t = [UInt64](repeating: 0, count: 256)
    for i in 0..<256 {
      var crc = UInt64(i)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ iso
        } else {
          crc >>= 1
        }
      }
      t[i] = crc
    }
    return t
  }()

  public func hash(_ content: String) -> String {
    var crc: UInt64 = ~0  // Go xors the running crc with all-ones on entry.
    for byte in content.utf8 {
      crc = Self.table[Int((crc ^ UInt64(byte)) & 0xFF)] ^ (crc >> 8)
    }
    crc = ~crc
    return HexEncoding.encode(bigEndianBytes(crc))
  }
}

/// A ``ContentHasher`` backed by the FNV-1a 128-bit hash (Go `hash/fnv.New128a`).
///
/// FNV has no CryptoKit analogue and needs 128-bit modular arithmetic, done here with a pair of
/// `UInt64` (`hi`, `lo`) and full-width multiplication. The 16-byte big-endian digest matches Go's
/// `New128a` output exactly (validated by known-answer test).
///
/// - Warning: non-cryptographic. See the file-level note.
public struct FNVHasher: ContentHasher {
  public init() {}

  // 128-bit FNV offset basis: 0x6c62272e07bb0142_62b821756295c58d.
  private static let offsetHi: UInt64 = 0x6c62_272e_07bb_0142
  private static let offsetLo: UInt64 = 0x62b8_2175_6295_c58d
  // 128-bit FNV prime: 2^88 + 2^8 + 0x3b = 0x00000000_01000000_00000000_0000013b.
  private static let primeHi: UInt64 = 0x0000_0000_0100_0000
  private static let primeLo: UInt64 = 0x0000_0000_0000_013b

  public func hash(_ content: String) -> String {
    var hi = Self.offsetHi
    var lo = Self.offsetLo
    for byte in content.utf8 {
      lo ^= UInt64(byte)  // FNV-1a: XOR the byte in first, then multiply.
      (hi, lo) = Self.multiply(hi, lo, Self.primeHi, Self.primeLo)
    }
    return HexEncoding.encode(bigEndianBytes(hi) + bigEndianBytes(lo))
  }

  /// Low 128 bits of a 128-bit × 128-bit product, returned as (hi, lo).
  private static func multiply(
    _ aHi: UInt64, _ aLo: UInt64, _ bHi: UInt64, _ bLo: UInt64
  ) -> (UInt64, UInt64) {
    let (llHi, llLo) = aLo.multipliedFullWidth(by: bLo)
    // Cross terms only contribute to the high word (their overflow past 2^128 is discarded).
    let hi = llHi &+ (aLo &* bHi) &+ (aHi &* bLo)
    return (hi, llLo)
  }
}

/// Big-endian byte expansion of a fixed-width unsigned integer, matching Go's `Sum` methods which
/// append the digest most-significant-byte first.
private func bigEndianBytes<T: FixedWidthInteger & UnsignedInteger>(_ value: T) -> [UInt8] {
  let width = T.bitWidth / 8
  var out = [UInt8](repeating: 0, count: width)
  for i in 0..<width {
    out[i] = UInt8(truncatingIfNeeded: value >> ((width - 1 - i) * 8))
  }
  return out
}
