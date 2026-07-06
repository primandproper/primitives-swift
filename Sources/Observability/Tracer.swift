import Foundation
import os

/// The role a span plays in a trace, ported from OpenTelemetry's `SpanKind`. Carried on span start so
/// an exporter (e.g. ``ObservabilityOTel``) can map it to the OTel kind; on the signpost backend it
/// rides the interval message. Default is ``internal``.
public enum SpanKind: String, Sendable, Equatable, Codable {
  case client
  case server
  case `internal`
  case producer
  case consumer
}

/// The completion status of a span, ported from OpenTelemetry's status codes. `unset` is the default
/// until a caller records success or failure via ``Span/setStatus(_:)``.
public enum SpanStatus: String, Sendable, Equatable, Codable {
  case ok
  case error
  case unset
}

/// Starts spans, ported from platform-go's `tracing.Tracer`. A tracer reads ``SpanContextStore/current``
/// to link each new span to the one in scope.
public protocol Tracer: Sendable {
  /// The full start form. `kind` classifies the span and `attributes` seed it before any body runs.
  /// The bare/partial overloads below funnel here, so existing `startSpan(name)` call sites are
  /// unchanged.
  func startSpan(_ name: String, kind: SpanKind, attributes: [String: AttributeValue]) -> any Span

  /// Returns a tracer scoped to a component. On the signpost backend the component rides the signpost
  /// category so Instruments can group spans by component; other backends may ignore it. Default:
  /// returns `self` unchanged.
  func named(_ component: String) -> any Tracer
}

extension Tracer {
  /// Bare start — default kind ``SpanKind/internal``, no initial attributes. Preserves the original
  /// `startSpan(_:)` API so existing call sites need no change.
  public func startSpan(_ name: String) -> any Span {
    startSpan(name, kind: .internal, attributes: [:])
  }

  /// Start with a kind but no initial attributes.
  public func startSpan(_ name: String, kind: SpanKind) -> any Span {
    startSpan(name, kind: kind, attributes: [:])
  }

  /// Start with initial attributes but the default kind.
  public func startSpan(_ name: String, attributes: [String: AttributeValue]) -> any Span {
    startSpan(name, kind: .internal, attributes: attributes)
  }

  /// Default per-component naming is a no-op; backends that can carry a component (``SignpostTracer``)
  /// override this.
  public func named(_ component: String) -> any Tracer { self }
}

/// A unit of work, ported from `tracing.Span`. Conformers are `Sendable` so a span can be carried
/// alongside an `Operation` across suspension points.
public protocol Span: Sendable {
  var name: String { get }
  var context: SpanContext { get }
  func attach(_ key: String, _ value: AttributeValue)
  func recordError(_ description: String, _ error: Error)
  /// Sets the span's completion status. Backends surface it however they can (an exporter maps it to
  /// the OTel status; the signpost backend emits it as an event).
  func setStatus(_ status: SpanStatus)
  func end()
}

extension Span {
  /// Sugar over ``attach(_:_:)`` accepting any ``AttributeRepresentable`` so scalar call sites
  /// (`span.attach("count", n)`) don't need an explicit `.int`/`.string`.
  public func attach(_ key: String, _ value: some AttributeRepresentable) {
    attach(key, value.attributeValue)
  }
}

// MARK: - Signpost (default iOS backend)

/// Default tracer: emits `OSSignposter` intervals, which render as spans in Instruments with zero
/// infrastructure. Because signpost names must be `StaticString`, the dynamic operation name, ids, and
/// span kind ride in the interval message instead. The dynamic component name (see ``named(_:)``) rides
/// the signpost *category* so Instruments can group spans by component.
public struct SignpostTracer: Tracer {
  /// The signpost category. Defaults to `"spans"`; ``named(_:)`` derives `"spans.<component>"`.
  public let category: String
  private let subsystem: String
  private let signposter: OSSignposter

  public init(
    subsystem: String = Bundle.main.bundleIdentifier ?? "platform-swift",
    category: String = "spans"
  ) {
    self.subsystem = subsystem
    self.category = category
    self.signposter = OSSignposter(subsystem: subsystem, category: category)
  }

  public func startSpan(_ name: String, kind: SpanKind, attributes: [String: AttributeValue])
    -> any Span
  {
    let span = SignpostSpan(
      name: name, kind: kind, context: .child(of: SpanContextStore.current),
      signposter: signposter)
    for (key, value) in attributes { span.attach(key, value) }
    return span
  }

  /// Scopes the tracer to a component by extending the signpost category to `"<category>.<component>"`,
  /// so Instruments can group intervals by component.
  public func named(_ component: String) -> any Tracer {
    SignpostTracer(subsystem: subsystem, category: "\(category).\(component)")
  }
}

public final class SignpostSpan: Span, @unchecked Sendable {
  public let name: String
  public let kind: SpanKind
  public let context: SpanContext

  private let signposter: OSSignposter
  private let signpostID: OSSignpostID
  private let state: OSAllocatedUnfairLock<IntervalState>

  private struct IntervalState {
    var interval: OSSignpostIntervalState?
    var ended: Bool
  }

  init(name: String, kind: SpanKind = .internal, context: SpanContext, signposter: OSSignposter) {
    self.name = name
    self.kind = kind
    self.context = context
    self.signposter = signposter
    self.signpostID = signposter.makeSignpostID()
    // The interval name must be a `StaticString`, so it's the static literal "span"; the dynamic name,
    // kind, and ids ride the message.
    let interval = signposter.beginInterval(
      "span", id: signpostID,
      "\(name, privacy: .public) kind=\(kind.rawValue, privacy: .public) span=\(context.spanID, privacy: .public) trace=\(context.traceID, privacy: .public)"
    )
    self.state = OSAllocatedUnfairLock(
      initialState: IntervalState(interval: interval, ended: false))
  }

  public func attach(_ key: String, _ value: AttributeValue) {
    signposter.emitEvent(
      "attr", id: signpostID,
      "\(key, privacy: .public)=\(value.rendered, privacy: .private)")
  }

  public func recordError(_ description: String, _ error: Error) {
    // Record the error as OTel-semconv `exception.*` attributes so an exporter can surface a typed
    // exception, then emit the human-readable signpost event for Instruments.
    attach(Keys.exceptionType, String(describing: type(of: error)))
    attach(Keys.exceptionMessage, String(describing: error))
    signposter.emitEvent(
      "error", id: signpostID,
      "\(description, privacy: .public): \(String(describing: error), privacy: .private)")
  }

  public func setStatus(_ status: SpanStatus) {
    // The signpost backend has no native status field; emit it as a public event so it's visible in
    // Instruments. An exporter backend overrides this to set the real OTel status.
    signposter.emitEvent("status", id: signpostID, "\(status.rawValue, privacy: .public)")
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
  public func startSpan(_ name: String, kind: SpanKind, attributes: [String: AttributeValue])
    -> any Span
  {
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
  public func attach(_ key: String, _ value: AttributeValue) {}
  public func recordError(_ description: String, _ error: Error) {}
  public func setStatus(_ status: SpanStatus) {}
  public func end() {}
}
