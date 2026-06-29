import Foundation
import os

/// Starts spans, ported from platform-go's `tracing.Tracer`. A tracer reads ``SpanContextStore/current``
/// to link each new span to the one in scope.
public protocol Tracer: Sendable {
  func startSpan(_ name: String) -> any Span
}

/// A unit of work, ported from `tracing.Span`. Conformers are `Sendable` so a span can be carried
/// alongside an `Operation` across suspension points.
public protocol Span: Sendable {
  var name: String { get }
  var context: SpanContext { get }
  func attach(_ key: String, _ value: Any)
  func recordError(_ description: String, _ error: Error)
  func end()
}

// MARK: - Signpost (default iOS backend)

/// Default tracer: emits `OSSignposter` intervals, which render as spans in Instruments with zero
/// infrastructure. Because signpost names must be `StaticString`, the dynamic operation name and ids
/// ride in the interval message instead.
public struct SignpostTracer: Tracer {
  private let signposter: OSSignposter

  public init(
    subsystem: String = Bundle.main.bundleIdentifier ?? "platform-swift",
    category: String = "spans"
  ) {
    self.signposter = OSSignposter(subsystem: subsystem, category: category)
  }

  public func startSpan(_ name: String) -> any Span {
    SignpostSpan(name: name, context: .child(of: SpanContextStore.current), signposter: signposter)
  }
}

public final class SignpostSpan: Span, @unchecked Sendable {
  public let name: String
  public let context: SpanContext

  private let signposter: OSSignposter
  private let signpostID: OSSignpostID
  private let state: OSAllocatedUnfairLock<IntervalState>

  private struct IntervalState {
    var interval: OSSignpostIntervalState?
    var ended: Bool
  }

  init(name: String, context: SpanContext, signposter: OSSignposter) {
    self.name = name
    self.context = context
    self.signposter = signposter
    self.signpostID = signposter.makeSignpostID()
    let interval = signposter.beginInterval(
      "span", id: signpostID,
      "\(name, privacy: .public) span=\(context.spanID, privacy: .public) trace=\(context.traceID, privacy: .public)"
    )
    self.state = OSAllocatedUnfairLock(
      initialState: IntervalState(interval: interval, ended: false))
  }

  public func attach(_ key: String, _ value: Any) {
    signposter.emitEvent(
      "attr", id: signpostID,
      "\(key, privacy: .public)=\(String(describing: value), privacy: .public)")
  }

  public func recordError(_ description: String, _ error: Error) {
    signposter.emitEvent(
      "error", id: signpostID,
      "\(description, privacy: .public): \(String(describing: error), privacy: .public)")
  }

  public func end() {
    state.withLock { s in
      guard !s.ended, let interval = s.interval else { return }
      signposter.endInterval("span", interval)
      s.ended = true
      s.interval = nil
    }
  }
}

// MARK: - Noop

public struct NoopTracer: Tracer {
  public init() {}
  public func startSpan(_ name: String) -> any Span {
    NoopSpan(name: name, context: .child(of: SpanContextStore.current))
  }
}

public final class NoopSpan: Span {
  public let name: String
  public let context: SpanContext
  public init(name: String, context: SpanContext) {
    self.name = name
    self.context = context
  }
  public func attach(_ key: String, _ value: Any) {}
  public func recordError(_ description: String, _ error: Error) {}
  public func end() {}
}
