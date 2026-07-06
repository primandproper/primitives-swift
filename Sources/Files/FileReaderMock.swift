import Foundation
import os

/// A test double for ``FileReader``. There is no Go moq-generated mock to port from — the `files`
/// package has no reader indirection in Go, so nothing there ever needed one — so this follows the same
/// recording-plus-handler shape ``Encoding``'s `MockClientEncoder` and ``Analytics``'s
/// `EventReporterMock` use elsewhere in this port.
///
/// A plain `final class` guarded by an `OSAllocatedUnfairLock`, not an `actor`: ``FileReader``'s
/// `lines(atPath:)`/`chunks(atPath:size:)` are synchronous `throws`, so an actor would force every call
/// site through `await` for a method that does no asynchronous work of its own. The handler closures are
/// `let`, injected once at ``init`` — the same reasoning ``EventReporterMock`` documents: a `public var`
/// couldn't be reassigned across isolation domains anyway once this were made an actor, so construction
/// time is the one place configuration happens.
public final class FileReaderMock: FileReader, @unchecked Sendable {
  public struct ChunksCall: Sendable, Equatable {
    public let path: String
    public let size: Int
  }

  public struct SliceLinesCall: Sendable, Equatable {
    public let path: String
    public let offset: Int
    public let count: Int
  }

  private struct State {
    var linesCalls: [String] = []
    var chunksCalls: [ChunksCall] = []
    var sliceLinesCalls: [SliceLinesCall] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  private let linesHandler: (@Sendable (String) throws -> AsyncThrowingStream<String, Error>)?
  private let chunksHandler:
    (@Sendable (String, Int) throws -> AsyncThrowingStream<[String], Error>)?
  private let sliceLinesHandler: (@Sendable (String, Int, Int) async throws -> [String])?

  /// - Parameters:
  ///   - linesHandler: run by every ``lines(atPath:)`` call; the default returns an already-finished,
  ///     empty sequence (never throws).
  ///   - chunksHandler: run by every ``chunks(atPath:size:)`` call; the default returns an
  ///     already-finished, empty sequence (never throws).
  ///   - sliceLinesHandler: run by every ``sliceLines(atPath:offset:count:)`` call; the default returns
  ///     an empty array (never throws).
  public init(
    linesHandler: (@Sendable (String) throws -> AsyncThrowingStream<String, Error>)? = nil,
    chunksHandler: (@Sendable (String, Int) throws -> AsyncThrowingStream<[String], Error>)? = nil,
    sliceLinesHandler: (@Sendable (String, Int, Int) async throws -> [String])? = nil
  ) {
    self.linesHandler = linesHandler
    self.chunksHandler = chunksHandler
    self.sliceLinesHandler = sliceLinesHandler
  }

  /// The `path` argument of every ``lines(atPath:)`` call, in order.
  public var linesCalls: [String] { state.withLock { $0.linesCalls } }
  /// The arguments of every ``chunks(atPath:size:)`` call, in order.
  public var chunksCalls: [ChunksCall] { state.withLock { $0.chunksCalls } }
  /// The arguments of every ``sliceLines(atPath:offset:count:)`` call, in order.
  public var sliceLinesCalls: [SliceLinesCall] { state.withLock { $0.sliceLinesCalls } }

  public func lines(atPath path: String) throws -> AsyncThrowingStream<String, Error> {
    state.withLock { $0.linesCalls.append(path) }
    guard let linesHandler else {
      return AsyncThrowingStream<String, Error> { $0.finish() }
    }
    return try linesHandler(path)
  }

  public func chunks(atPath path: String, size: Int) throws -> AsyncThrowingStream<[String], Error>
  {
    state.withLock { $0.chunksCalls.append(ChunksCall(path: path, size: size)) }
    guard let chunksHandler else {
      return AsyncThrowingStream<[String], Error> { $0.finish() }
    }
    return try chunksHandler(path, size)
  }

  public func sliceLines(atPath path: String, offset: Int, count: Int) async throws -> [String] {
    state.withLock {
      $0.sliceLinesCalls.append(SliceLinesCall(path: path, offset: offset, count: count))
    }
    guard let sliceLinesHandler else { return [] }
    return try await sliceLinesHandler(path, offset, count)
  }
}
