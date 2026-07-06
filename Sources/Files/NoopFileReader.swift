import Foundation

/// A no-op ``FileReader`` that yields no lines/chunks and returns an empty windowed read, touching the
/// filesystem for nothing. Go's `files` package ships no `noop` subpackage (every caller uses the
/// package-level functions directly, with no reader indirection to no-op out), but every other
/// protocol-bearing module in this port ships one — see the port's settled rules. Useful as the safe
/// default when no reader should touch disk (a feature-flag-off path, a SwiftUI preview target).
public struct NoopFileReader: FileReader {
  public init() {}

  public func lines(atPath path: String) throws -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream<String, Error> { $0.finish() }
  }

  public func chunks(atPath path: String, size: Int) throws -> AsyncThrowingStream<[String], Error>
  {
    AsyncThrowingStream<[String], Error> { $0.finish() }
  }

  public func sliceLines(atPath path: String, offset: Int, count: Int) async throws -> [String] {
    []
  }
}
