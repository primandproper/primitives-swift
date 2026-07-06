import os

/// Which pillar an observation landed on. Mirrors platform-go's `recording.Pillar`.
public enum Pillar: Sendable, Equatable {
  case both
  case span
  case log
}

/// A single recorded attachment with a global sequence number, so tests can assert ordering across
/// operations. Ported from platform-go's `recording.Observation`.
public struct Observation: Sendable, Equatable {
  public let key: String
  public let value: String
  public let pillar: Pillar
  public let seq: Int
}

/// Test-only `Observer` that captures observations instead of emitting them, ported from
/// `recording.RecordingObserver`. Use ``recordingObserver(_:)`` to build one.
public final class RecordingObserver: Observer, @unchecked Sendable {
  public let name: String
  public let logger: any Logger = NoopLogger()
  public let tracer: any Tracer = NoopTracer()

  private let state = OSAllocatedUnfairLock(initialState: State())
  private struct State {
    var operations: [RecordingOperation] = []
    var seq = 0
  }

  public init(name: String) {
    self.name = name
  }

  public var operations: [RecordingOperation] { state.withLock { $0.operations } }

  public func operation<R>(name: String, _ body: (any Operation) async throws -> R) async rethrows
    -> R
  {
    let op = makeOperation(name: name)
    return try await SpanContextStore.$current.withValue(op.span.context) {
      defer { op.end() }
      return try await body(op)
    }
  }

  public func begin(name: String) -> any Operation {
    makeOperation(name: name)
  }

  private func makeOperation(name: String) -> RecordingOperation {
    let context = SpanContext.child(of: SpanContextStore.current)
    let op = RecordingOperation(
      name: name, context: context,
      nextSeq: { [weak self] in
        self?.state.withLock {
          $0.seq += 1
          return $0.seq
        } ?? 0
      })
    state.withLock { $0.operations.append(op) }
    return op
  }
}

/// Test-only `Operation` capturing each attachment with its pillar. Ported from
/// `recording.RecordingOperation`.
public final class RecordingOperation: Operation, @unchecked Sendable {
  public let name: String
  public let span: any Span
  public let logger: any Logger = NoopLogger()

  private let nextSeq: @Sendable () -> Int
  private let state = OSAllocatedUnfairLock(initialState: State())
  private struct State {
    var observations: [Observation] = []
    var errors: [(context: String, error: String)] = []
    var acknowledgements: [String] = []
    var ended = false
  }

  init(name: String, context: SpanContext, nextSeq: @escaping @Sendable () -> Int) {
    self.name = name
    self.span = NoopSpan(name: name, context: context)
    self.nextSeq = nextSeq
  }

  // MARK: Captured state (for assertions)

  public var observations: [Observation] { state.withLock { $0.observations } }
  public var recordedErrors: [(context: String, error: String)] { state.withLock { $0.errors } }
  /// Descriptions passed to a successful `acknowledge(nil, …)`, mirroring the info log the production
  /// operation writes on the success path so tests can observe it.
  public var acknowledgements: [String] { state.withLock { $0.acknowledgements } }
  public var ended: Bool { state.withLock { $0.ended } }

  /// Keys seen on a given pillar (`both` always counts toward span and log too).
  public func keys(on pillar: Pillar? = nil) -> [String] {
    observations
      .filter { pillar == nil || $0.pillar == pillar || $0.pillar == .both }
      .map(\.key)
  }

  public func value(forKey key: String) -> String? {
    observations.first { $0.key == key }?.value
  }

  // MARK: Operation

  private func record(_ key: String, _ value: AttributeValue, _ pillar: Pillar) {
    let obs = Observation(
      key: key, value: value.rendered, pillar: pillar, seq: nextSeq())
    state.withLock { $0.observations.append(obs) }
  }

  @discardableResult
  public func set(_ key: String, _ value: AttributeValue) -> any Operation {
    record(key, value, .both)
    return self
  }

  @discardableResult
  public func setValues(_ values: [String: AttributeValue]) -> any Operation {
    for (k, v) in values.sorted(by: { $0.key < $1.key }) { record(k, v, .both) }
    return self
  }

  @discardableResult
  public func spanOnly(_ key: String, _ value: AttributeValue) -> any Operation {
    record(key, value, .span)
    return self
  }

  @discardableResult
  public func logOnly(_ key: String, _ value: AttributeValue) -> any Operation {
    record(key, value, .log)
    return self
  }

  @discardableResult
  public func error(_ error: Error, _ description: String) -> Error {
    state.withLock { $0.errors.append((description, String(describing: error))) }
    return ObservabilityError(description, error)
  }

  public func acknowledge(_ error: Error?, _ description: String) {
    if let error {
      state.withLock { $0.errors.append((description, String(describing: error))) }
    } else {
      // LiveOperation logs `info(description)` on the success path; capture it so tests observing an
      // acknowledged success aren't blind to it.
      state.withLock { $0.acknowledgements.append(description) }
    }
  }

  public func end() {
    state.withLock { $0.ended = true }
  }
}
