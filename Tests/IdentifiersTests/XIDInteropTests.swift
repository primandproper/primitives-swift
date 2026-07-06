import Foundation
import Testing

@testable import Identifiers

/// Cross-language interop (REPO-07): xid strings minted by Go's `github.com/rs/xid`, pinned alongside
/// their decoded components, that Swift's xid support must accept and re-encode identically.
///
/// Swift exposes an xid *encoder* (``XIDGenerator/encode(_:)``) and a *validator*
/// (``Identifier/isValid(_:)``) but no decoder, so the interop check is: given the exact 12 raw bytes
/// Go decoded an id into, Swift's encoder must reproduce Go's 20-character string, and Swift must
/// validate that string. That is a genuine byte-level parity check against real rs/xid output.
///
/// Two of these ids are the same values embedded in the JWT test token's `jti`/`sub`
/// (`Tests/AuthenticationTests/JWTTests.swift`), now proven to be genuine rs/xid values with the
/// components Go decodes from them.
///
/// ## How the fixtures were produced (reproducible)
///
/// Toolchain `go1.26.4 darwin/arm64`, `github.com/rs/xid v1.6.0`:
///
/// ```go
/// id, _ := xid.FromString("crsa076tg3qdtmccq90g")
/// fmt.Printf("%x %d %x %d %d\n",
///   id.Bytes(), id.Time().Unix(), id.Machine(), id.Pid(), id.Counter())
/// // The third id was freshly minted with xid.New().
/// ```
private struct XIDVector {
  let string: String
  let rawBytes: [UInt8]
  let unixSeconds: Int64
  let machineHex: String
  let pid: UInt16
  let counter: Int32
}

@Suite("xid Go→Swift interop (REPO-07)")
struct XIDInteropTests {
  /// Fixtures decoded by rs/xid. `rawBytes` is `id.Bytes()`; the remaining fields are the decoded
  /// timestamp/machine/pid/counter, pinned for documentation and the timestamp-prefix parity check.
  private let vectors: [XIDVector] = [
    // From the JWT test token's `sub`.
    XIDVector(
      string: "crsa076tg3qdtmccq90g",
      rawBytes: [0x66, 0xf8, 0xa0, 0x1c, 0xdd, 0x80, 0xf4, 0xde, 0xd9, 0x8c, 0xd2, 0x41],
      unixSeconds: 1_727_569_948, machineHex: "dd80f4", pid: 57049, counter: 9_228_865),
    // From the JWT test token's `jti`.
    XIDVector(
      string: "crsa076tg3qdtmccq910",
      rawBytes: [0x66, 0xf8, 0xa0, 0x1c, 0xdd, 0x80, 0xf4, 0xde, 0xd9, 0x8c, 0xd2, 0x42],
      unixSeconds: 1_727_569_948, machineHex: "dd80f4", pid: 57049, counter: 9_228_866),
    // A freshly minted xid.New() from the same run.
    XIDVector(
      string: "d95k6ccn9qd0d05iurdg",
      rawBytes: [0x6a, 0x4b, 0x43, 0x31, 0x97, 0x4e, 0x9a, 0x06, 0x80, 0xb2, 0xf6, 0xdb],
      unixSeconds: 1_783_317_297, machineHex: "974e9a", pid: 1664, counter: 11_728_603),
  ]

  @Test("Swift re-encodes Go's raw bytes to the exact Go string")
  func encodeMatchesGo() {
    for v in vectors {
      #expect(XIDGenerator.encode(v.rawBytes) == v.string)
    }
  }

  @Test("Swift validates every Go-minted xid string")
  func validatesGoStrings() {
    for v in vectors {
      #expect(Identifier.isValid(v.string))
    }
  }

  @Test("the 4-byte big-endian timestamp prefix matches Go's decoded time")
  func timestampPrefixMatchesGo() {
    for v in vectors {
      // xid stores uint32(Unix seconds) big-endian in bytes 0..3; Swift's timestamp encoder must
      // reproduce those exact four leading bytes from the id's decoded Unix time.
      let ts = XIDGenerator.timestamp(forUnixSeconds: Double(v.unixSeconds))
      let prefix: [UInt8] = [
        UInt8(truncatingIfNeeded: ts >> 24),
        UInt8(truncatingIfNeeded: ts >> 16),
        UInt8(truncatingIfNeeded: ts >> 8),
        UInt8(truncatingIfNeeded: ts),
      ]
      #expect(Array(v.rawBytes.prefix(4)) == prefix)
    }
  }

  @Test("machine/pid/counter bytes sit where rs/xid places them")
  func componentByteLayout() {
    for v in vectors {
      // machine = bytes 4..6, pid = bytes 7..8 (big-endian), counter = bytes 9..11 (big-endian).
      let machine = v.rawBytes[4...6].map { String(format: "%02x", $0) }.joined()
      #expect(machine == v.machineHex)

      let pid = UInt16(v.rawBytes[7]) << 8 | UInt16(v.rawBytes[8])
      #expect(pid == v.pid)

      let counter =
        Int32(v.rawBytes[9]) << 16 | Int32(v.rawBytes[10]) << 8 | Int32(v.rawBytes[11])
      #expect(counter == v.counter)
    }
  }
}
