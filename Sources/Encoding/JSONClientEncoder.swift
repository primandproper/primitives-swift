import Foundation

/// A ``ClientEncoder`` backed by Foundation's `JSONEncoder`/`JSONDecoder`, ported from the JSON branch
/// of platform-go's `clientEncoder` (`encoding/client_encoder.go`), where JSON was the `default` codec.
///
/// A fresh `JSONEncoder`/`JSONDecoder` is created per call rather than stored: both are reference types
/// with mutable configuration, so keeping them out of stored state lets this stay a value type that is
/// trivially `Sendable` under strict concurrency. They're cheap to allocate, so this costs nothing that
/// matters at the plausible call volume.
///
/// **Difference from the Go server decoder:** Go's *server*-side decoder set
/// `dec.DisallowUnknownFields()`. That is a server-request-validation concern (rejecting unexpected
/// client input) and is out of scope for this client-side port — Foundation's `JSONDecoder` ignores
/// unknown keys, matching Go's *client* encoder, which never set that flag.
public struct JSONClientEncoder: ClientEncoder {
  public let contentType: ContentType = .json

  /// Optionally customizes the encoder/decoder (date strategy, key strategy, output formatting). The
  /// defaults match Go's `encoding/json` defaults, so leaving these unset round-trips with a Go peer.
  private let configureEncoder: @Sendable (JSONEncoder) -> Void
  private let configureDecoder: @Sendable (JSONDecoder) -> Void

  public init(
    configureEncoder: @escaping @Sendable (JSONEncoder) -> Void = { _ in },
    configureDecoder: @escaping @Sendable (JSONDecoder) -> Void = { _ in }
  ) {
    self.configureEncoder = configureEncoder
    self.configureDecoder = configureDecoder
  }

  public func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    configureEncoder(encoder)
    return try encoder.encode(value)
  }

  public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    configureDecoder(decoder)
    return try decoder.decode(type, from: data)
  }
}
