/// Standard (padded) RFC 4648 base32 encoding, matching Go's `encoding/base32.StdEncoding`.
///
/// Foundation ships base64 but no base32, so we implement the encoder directly. Only encoding is
/// needed — the Go package never decodes — so this stays deliberately minimal.
enum Base32 {
  private static let alphabet: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
  private static let padding = UInt8(ascii: "=")

  /// Encodes `data` into padded base32. Empty input yields the empty string, matching Go.
  static func standardEncode(_ data: [UInt8]) -> String {
    guard !data.isEmpty else { return "" }

    var out = [UInt8]()
    out.reserveCapacity((data.count + 4) / 5 * 8)

    var index = 0
    let count = data.count
    while index < count {
      // Gather up to five input bytes; missing bytes stay zero and drive the padding count.
      var block = [UInt8](repeating: 0, count: 5)
      var present = 0
      for offset in 0..<5 where index + offset < count {
        block[offset] = data[index + offset]
        present += 1
      }

      let quintet: [Int] = [
        Int(block[0] >> 3),
        Int((block[0] << 2 | block[1] >> 6) & 0x1f),
        Int((block[1] >> 1) & 0x1f),
        Int((block[1] << 4 | block[2] >> 4) & 0x1f),
        Int((block[2] << 1 | block[3] >> 7) & 0x1f),
        Int((block[3] >> 2) & 0x1f),
        Int((block[3] << 3 | block[4] >> 5) & 0x1f),
        Int(block[4] & 0x1f),
      ]

      // How many of the eight output characters carry real data, per RFC 4648.
      let significant: Int
      switch present {
      case 1: significant = 2
      case 2: significant = 4
      case 3: significant = 5
      case 4: significant = 7
      default: significant = 8
      }

      for position in 0..<8 {
        out.append(position < significant ? alphabet[quintet[position]] : padding)
      }
      index += 5
    }

    return String(decoding: out, as: UTF8.self)
  }
}
