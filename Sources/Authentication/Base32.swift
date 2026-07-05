import Foundation

/// RFC 4648 base32 (standard alphabet) decoding, matching how `github.com/pquerna/otp` decodes a TOTP
/// shared secret.
///
/// pquerna's `hotp.GenerateCodeCustom` normalizes the secret before decoding: it `TrimSpace`s the ends,
/// right-pads with `=` to a multiple of 8, upper-cases it, then runs `base32.StdEncoding.DecodeString`
/// (issues #10/#17/#24 in that library). We reproduce that normalization exactly so any secret the Go
/// side accepts decodes to the identical key bytes here — the whole point being that codes match.
///
/// Decoding is lenient about the trailing partial group's spare bits (they are discarded, as an
/// over-strict decoder would reject otherwise-valid authenticator secrets), and returns `nil` for any
/// character outside the alphabet — the caller maps that to ``TOTPError/invalidSecret``.
enum Base32 {
  private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)

  /// Reverse lookup table: ASCII byte -> 5-bit value, or 0xFF for "not in the alphabet".
  private static let reverse: [UInt8] = {
    var table = [UInt8](repeating: 0xFF, count: 256)
    for (index, char) in alphabet.enumerated() {
      table[Int(char)] = UInt8(index)
    }
    return table
  }()

  /// Decodes a standard-alphabet base32 string to its raw bytes, applying pquerna's secret
  /// normalization (trim, upper-case, tolerate missing padding). Returns `nil` on any invalid character.
  static func decode(_ input: String) -> Data? {
    // Mirror pquerna: trim surrounding whitespace, then upper-case. Internal whitespace is (as in Go)
    // treated as invalid rather than stripped, keeping us wire-faithful.
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    var output = [UInt8]()
    output.reserveCapacity(trimmed.utf8.count * 5 / 8)

    var buffer: UInt32 = 0
    var bitsInBuffer: UInt32 = 0

    for byte in trimmed.utf8 {
      if byte == UInt8(ascii: "=") {
        // Padding: everything meaningful has been consumed by this point.
        break
      }
      let value = reverse[Int(byte)]
      if value == 0xFF {
        return nil
      }
      buffer = (buffer << 5) | UInt32(value)
      bitsInBuffer += 5
      if bitsInBuffer >= 8 {
        bitsInBuffer -= 8
        output.append(UInt8((buffer >> bitsInBuffer) & 0xFF))
      }
    }

    return Data(output)
  }
}
