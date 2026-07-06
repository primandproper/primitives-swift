import Foundation

/// W3C Trace Context propagation for the `traceparent` (and pass-through `tracestate`) HTTP headers.
///
/// This is the outbound/inbound seam that lets a ``SpanContext`` cross a network boundary: HTTPClient
/// (NET-23) injects the current span onto a `URLRequest` so the server continues the same trace, and
/// can extract an incoming `traceparent` back into a ``SpanContext``.
///
/// It lives in core `Observability` — not `ObservabilityOTel` — deliberately: it is implementable
/// purely from ``SpanContext`` with no OpenTelemetry dependency, and HTTPClient already depends on
/// `Observability`. Keeping it here means NET-23 consumes it without pulling in the heavy OTel graph
/// that `ObservabilityOTel` is reserved for.
///
/// Reference: <https://www.w3.org/TR/trace-context/>
public enum W3CPropagation {

  /// Canonical (lowercase) HTTP header name carrying the `version-traceid-parentid-flags` value.
  public static let traceparentHeader = "traceparent"
  /// Canonical (lowercase) HTTP header name carrying vendor-specific trace state.
  public static let tracestateHeader = "tracestate"

  /// The only `traceparent` version this implementation emits and fully validates.
  private static let version = "00"
  /// `trace-flags` byte with the "sampled" bit set.
  private static let sampledFlags = "01"
  /// `trace-flags` byte with no bits set.
  private static let unsampledFlags = "00"

  // MARK: - Inject

  /// Builds the `traceparent` header value for `context`.
  ///
  /// Format: `00-{trace-id}-{parent-id}-{flags}` where `parent-id` is `context.spanID` (the span the
  /// remote peer should treat as its parent) and `flags` is `01` when `sampled`, else `00`.
  public static func traceparent(for context: SpanContext, sampled: Bool = true) -> String {
    "\(version)-\(context.traceID)-\(context.spanID)-\(sampled ? sampledFlags : unsampledFlags)"
  }

  /// Returns the header key/value pairs to attach to an outbound request.
  ///
  /// Always includes `traceparent`; includes `tracestate` only when a non-empty value is supplied.
  public static func headers(
    for context: SpanContext, tracestate: String? = nil, sampled: Bool = true
  ) -> [String: String] {
    var headers = [traceparentHeader: traceparent(for: context, sampled: sampled)]
    if let tracestate, !tracestate.isEmpty {
      headers[tracestateHeader] = tracestate
    }
    return headers
  }

  /// Sets the `traceparent` (and optional `tracestate`) header on `request` in place.
  public static func inject(
    _ context: SpanContext, into request: inout URLRequest, tracestate: String? = nil,
    sampled: Bool = true
  ) {
    for (name, value) in headers(for: context, tracestate: tracestate, sampled: sampled) {
      request.setValue(value, forHTTPHeaderField: name)
    }
  }

  // MARK: - Extract

  /// Parses a `traceparent` header value into a ``SpanContext``, returning `nil` when the value is
  /// malformed per the W3C spec.
  ///
  /// The returned context's ``SpanContext/spanID`` is the header's `parent-id` (the remote span) and
  /// ``SpanContext/parentSpanID`` is `nil` — the wire format carries no grandparent. `tracestate` is
  /// accepted for symmetry but does not affect the parsed identity.
  ///
  /// Rejects: wrong version, wrong field count, wrong field lengths, non-hex digits, and the
  /// all-zero (invalid) trace-id or parent-id.
  public static func extract(traceparent: String, tracestate: String? = nil) -> SpanContext? {
    let fields = traceparent.split(separator: "-", omittingEmptySubsequences: false)
    // version-traceid-parentid-flags — exactly four fields for version 00.
    guard fields.count == 4 else { return nil }

    let versionField = String(fields[0])
    let traceID = String(fields[1])
    let parentID = String(fields[2])
    let flags = String(fields[3])

    guard versionField == version else { return nil }
    guard isHex(traceID, length: 32), traceID != allZero(32) else { return nil }
    guard isHex(parentID, length: 16), parentID != allZero(16) else { return nil }
    guard isHex(flags, length: 2) else { return nil }

    return SpanContext(traceID: traceID, spanID: parentID, parentSpanID: nil)
  }

  /// Extracts a ``SpanContext`` from the `traceparent` header on `request`, if present and valid.
  public static func extract(from request: URLRequest) -> SpanContext? {
    guard let value = request.value(forHTTPHeaderField: traceparentHeader) else { return nil }
    return extract(traceparent: value, tracestate: request.value(forHTTPHeaderField: tracestateHeader))
  }

  // MARK: - Helpers

  /// True when `s` is exactly `length` lowercase hex digits (matching what W3C `00` requires on emit).
  private static func isHex(_ s: String, length: Int) -> Bool {
    guard s.utf8.count == length else { return false }
    for byte in s.utf8 {
      let isDigit = byte >= 0x30 && byte <= 0x39  // 0-9
      let isLowerAF = byte >= 0x61 && byte <= 0x66  // a-f
      if !isDigit && !isLowerAF { return false }
    }
    return true
  }

  private static func allZero(_ length: Int) -> String {
    String(repeating: "0", count: length)
  }
}
