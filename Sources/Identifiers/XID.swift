import Foundation

/// The xid base32-hex alphabet (RFC 4648 base32-hex, lowercased) that `github.com/rs/xid` uses.
private let encoding: [UInt8] = Array("0123456789abcdefghijklmnopqrstuv".utf8)

/// Reverse lookup: ASCII byte -> alphabet index, or -1 for characters outside the alphabet.
private let decoding: [Int8] = {
  var table = [Int8](repeating: -1, count: 256)
  for (index, char) in encoding.enumerated() {
    table[Int(char)] = Int8(index)
  }
  return table
}()

/// Generates xid values. Ported from `github.com/rs/xid`.
///
/// Marked `@unchecked Sendable`: the counter is the only mutable state and it is guarded by an
/// `NSLock`, so shared use across concurrency domains is safe. `os_unfair_lock` would be lighter,
/// but ID minting is nowhere near hot enough for that to matter (Pike's rule 3 — n is small).
final class XIDGenerator: @unchecked Sendable {
  static let shared = XIDGenerator()

  private let machineID: (UInt8, UInt8, UInt8)
  private let processID: UInt16
  private let lock = NSLock()
  private var counter: UInt32

  init() {
    machineID = Self.readMachineID()
    processID = UInt16(truncatingIfNeeded: ProcessInfo.processInfo.processIdentifier)
    // xid seeds the counter randomly so IDs minted early in two processes don't collide.
    counter = UInt32.random(in: 0...0xFF_FFFF)
  }

  /// Builds the raw 12-byte xid: 4-byte big-endian seconds timestamp, 3-byte machine ID,
  /// 2-byte big-endian PID, 3-byte big-endian counter.
  func newRawID() -> [UInt8] {
    let timestamp = UInt32(Date().timeIntervalSince1970)

    lock.lock()
    counter = (counter &+ 1) & 0xFF_FFFF
    let count = counter
    lock.unlock()

    var id = [UInt8](repeating: 0, count: 12)
    id[0] = UInt8(truncatingIfNeeded: timestamp >> 24)
    id[1] = UInt8(truncatingIfNeeded: timestamp >> 16)
    id[2] = UInt8(truncatingIfNeeded: timestamp >> 8)
    id[3] = UInt8(truncatingIfNeeded: timestamp)
    id[4] = machineID.0
    id[5] = machineID.1
    id[6] = machineID.2
    id[7] = UInt8(truncatingIfNeeded: processID >> 8)
    id[8] = UInt8(truncatingIfNeeded: processID)
    id[9] = UInt8(truncatingIfNeeded: count >> 16)
    id[10] = UInt8(truncatingIfNeeded: count >> 8)
    id[11] = UInt8(truncatingIfNeeded: count)
    return id
  }

  func newIDString() -> String {
    Self.encode(newRawID())
  }

  private static func readMachineID() -> (UInt8, UInt8, UInt8) {
    let host = ProcessInfo.processInfo.hostName
    if let data = host.data(using: .utf8), data.count >= 3 {
      // Cheap FNV-1a over the hostname to spread it across three bytes; xid uses MD5, but only the
      // format matters for validity, so we avoid pulling in a crypto dependency.
      var hash: UInt32 = 2_166_136_261
      for byte in data {
        hash = (hash ^ UInt32(byte)) &* 16_777_619
      }
      return (
        UInt8(truncatingIfNeeded: hash >> 16),
        UInt8(truncatingIfNeeded: hash >> 8),
        UInt8(truncatingIfNeeded: hash)
      )
    }
    return (
      UInt8.random(in: .min ... .max),
      UInt8.random(in: .min ... .max),
      UInt8.random(in: .min ... .max)
    )
  }

  /// Encodes a 12-byte xid into its 20-character string form. This is the unrolled base32-hex
  /// encoder from xid's `id.go`, transcribed verbatim; Swift's `<<`/`>>` are non-trapping smart
  /// shifts that drop overflow bits exactly as Go's byte shifts do.
  static func encode(_ id: [UInt8]) -> String {
    precondition(id.count == 12, "xid raw value must be 12 bytes")
    var dst = [UInt8](repeating: 0, count: 20)
    dst[0] = encoding[Int(id[0] >> 3)]
    dst[1] = encoding[Int((id[1] >> 6) & 0x1f | (id[0] << 2) & 0x1f)]
    dst[2] = encoding[Int((id[1] >> 1) & 0x1f)]
    dst[3] = encoding[Int((id[2] >> 4) & 0x1f | (id[1] << 4) & 0x1f)]
    dst[4] = encoding[Int((id[3] >> 7) | (id[2] << 1) & 0x1f)]
    dst[5] = encoding[Int((id[3] >> 2) & 0x1f)]
    dst[6] = encoding[Int((id[4] >> 5) | (id[3] << 3) & 0x1f)]
    dst[7] = encoding[Int(id[4] & 0x1f)]
    dst[8] = encoding[Int(id[5] >> 3)]
    dst[9] = encoding[Int((id[6] >> 6) & 0x1f | (id[5] << 2) & 0x1f)]
    dst[10] = encoding[Int((id[6] >> 1) & 0x1f)]
    dst[11] = encoding[Int((id[7] >> 4) & 0x1f | (id[6] << 4) & 0x1f)]
    dst[12] = encoding[Int((id[8] >> 7) | (id[7] << 1) & 0x1f)]
    dst[13] = encoding[Int((id[8] >> 2) & 0x1f)]
    dst[14] = encoding[Int((id[9] >> 5) | (id[8] << 3) & 0x1f)]
    dst[15] = encoding[Int(id[9] & 0x1f)]
    dst[16] = encoding[Int(id[10] >> 3)]
    dst[17] = encoding[Int((id[11] >> 6) & 0x1f | (id[10] << 2) & 0x1f)]
    dst[18] = encoding[Int((id[11] >> 1) & 0x1f)]
    dst[19] = encoding[Int((id[11] << 4) & 0x1f)]
    return String(decoding: dst, as: UTF8.self)
  }

  /// Validates a candidate xid string: exactly 20 characters, every character in the alphabet, and
  /// the canonical trailing-character constraint xid's `decode` enforces (a non-canonical final
  /// character means the string could not have been produced by `encode`).
  static func isValidIDString(_ string: String) -> Bool {
    let src = Array(string.utf8)
    guard src.count == 20 else { return false }
    for byte in src where decoding[Int(byte)] < 0 { return false }

    // Reconstruct the final data byte (id[11]) and confirm it re-encodes to the given last char.
    let d: (Int) -> UInt8 = { UInt8(bitPattern: decoding[Int(src[$0])]) }
    let id11 = (d(17) << 6) | (d(18) << 1) | (d(19) >> 4)
    return encoding[Int((id11 << 4) & 0x1f)] == src[19]
  }
}
