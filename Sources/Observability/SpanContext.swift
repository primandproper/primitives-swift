import Foundation

/// A span's identity and lineage, propagated implicitly across `async`/`await` via a task-local.
///
/// This is the Swift replacement for threading `context.Context` through every call in platform-go:
/// instead of returning a new `ctx` from `Begin`, an `Observer.operation` scope installs the new
/// span's context as ``SpanContextStore/current`` for the duration of its body, so nested operations
/// pick up their parent automatically. IDs are W3C-trace-context compatible hex.
public struct SpanContext: Sendable, Equatable {
  public let traceID: String
  public let spanID: String
  public let parentSpanID: String?

  public init(traceID: String, spanID: String, parentSpanID: String?) {
    self.traceID = traceID
    self.spanID = spanID
    self.parentSpanID = parentSpanID
  }

  /// Derives a child context from whatever is currently in scope, minting a fresh trace when there
  /// is no parent.
  public static func child(of parent: SpanContext?) -> SpanContext {
    SpanContext(
      traceID: parent?.traceID ?? IDGen.traceID(),
      spanID: IDGen.spanID(),
      parentSpanID: parent?.spanID
    )
  }
}

/// Holds the span context for the current task tree. Read by tracers when starting a span so the new
/// span links to its parent without any explicit plumbing.
public enum SpanContextStore {
  @TaskLocal public static var current: SpanContext?
}

enum IDGen {
  /// 128-bit trace id, 32 hex chars (W3C `trace-id`).
  ///
  /// Loops on the astronomically rare all-zero draw, which W3C declares an invalid trace-id.
  static func traceID() -> String {
    while true {
      let hi = UInt64.random(in: .min ... .max)
      let lo = UInt64.random(in: .min ... .max)
      if hi != 0 || lo != 0 {
        return String(format: "%016llx%016llx", hi, lo)
      }
    }
  }

  /// 64-bit span id, 16 hex chars (W3C `parent-id`).
  ///
  /// Loops on the astronomically rare all-zero draw, which W3C declares an invalid parent-id.
  static func spanID() -> String {
    while true {
      let value = UInt64.random(in: .min ... .max)
      if value != 0 {
        return String(format: "%016llx", value)
      }
    }
  }
}
