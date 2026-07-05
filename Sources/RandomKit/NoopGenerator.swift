/// A no-op ``RandomGenerator`` that returns empty results and never fails, ported from Go's
/// `random/noop` package. Useful as a stand-in in tests or wherever a generator is required but no
/// real randomness should be produced.
public struct NoopGenerator: RandomGenerator {
  public init() {}

  /// Returns an empty, non-nil byte array (matching Go's `[]byte{}`).
  public func generateRawBytes(length: Int) throws -> [UInt8] { [] }
  public func generateHexEncodedString(length: Int) throws -> String { "" }
  public func generateBase32EncodedString(length: Int) throws -> String { "" }
  public func generateBase64EncodedString(length: Int) throws -> String { "" }
}
