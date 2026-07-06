import Foundation
import Testing

@testable import Observability

@Suite("W3C Propagation")
struct W3CPropagationTests {

  @Test("traceparent inject produces version-traceid-parentid-flags")
  func injectFormat() {
    let ctx = SpanContext(
      traceID: "4bf92f3577b34da6a3ce929d0e0e4736", spanID: "00f067aa0ba902b7", parentSpanID: nil)
    #expect(
      W3CPropagation.traceparent(for: ctx)
        == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
    #expect(
      W3CPropagation.traceparent(for: ctx, sampled: false)
        == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00")
  }

  @Test("inject -> extract round-trips trace and span ids")
  func roundTrip() {
    let ctx = SpanContext.child(of: nil)
    let header = W3CPropagation.traceparent(for: ctx)
    let extracted = W3CPropagation.extract(traceparent: header)
    #expect(extracted?.traceID == ctx.traceID)
    // parent-id on the wire becomes the extracted span id.
    #expect(extracted?.spanID == ctx.spanID)
    #expect(extracted?.parentSpanID == nil)
  }

  @Test("inject/extract via URLRequest round-trips")
  func urlRequestRoundTrip() {
    let ctx = SpanContext.child(of: nil)
    var request = URLRequest(url: URL(string: "https://example.com")!)
    W3CPropagation.inject(ctx, into: &request, tracestate: "vendor=abc")

    #expect(request.value(forHTTPHeaderField: "traceparent") == W3CPropagation.traceparent(for: ctx))
    #expect(request.value(forHTTPHeaderField: "tracestate") == "vendor=abc")

    let extracted = W3CPropagation.extract(from: request)
    #expect(extracted?.traceID == ctx.traceID)
    #expect(extracted?.spanID == ctx.spanID)
  }

  @Test("headers omits tracestate when nil or empty")
  func headersOmitsEmptyTracestate() {
    let ctx = SpanContext.child(of: nil)
    #expect(W3CPropagation.headers(for: ctx)[W3CPropagation.tracestateHeader] == nil)
    #expect(W3CPropagation.headers(for: ctx, tracestate: "")[W3CPropagation.tracestateHeader] == nil)
    #expect(
      W3CPropagation.headers(for: ctx, tracestate: "a=b")[W3CPropagation.tracestateHeader] == "a=b")
  }

  @Test("extract rejects malformed traceparent values")
  func rejectsMalformed() {
    let valid = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    // Sanity: the valid baseline parses.
    #expect(W3CPropagation.extract(traceparent: valid) != nil)

    let bad = [
      "",  // empty
      "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",  // bad version
      "01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",  // unsupported version
      "00-4bf92f3577b34da6a3ce929d0e0e473-00f067aa0ba902b7-01",  // trace-id too short
      "00-4bf92f3577b34da6a3ce929d0e0e47366-00f067aa0ba902b7-01",  // trace-id too long
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b-01",  // parent-id too short
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-1",  // flags too short
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7",  // missing flags
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-extra",  // extra field
      "00-4bf92f3577b34da6a3ce929d0e0e473G-00f067aa0ba902b7-01",  // non-hex in trace-id
      "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01",  // uppercase (non-canonical)
      "00-00000000000000000000000000000000-00f067aa0ba902b7-01",  // all-zero trace-id
      "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01",  // all-zero parent-id
    ]
    for value in bad {
      #expect(W3CPropagation.extract(traceparent: value) == nil, "should reject: \(value)")
    }
  }

  @Test("extract from request without traceparent returns nil")
  func extractMissingHeader() {
    let request = URLRequest(url: URL(string: "https://example.com")!)
    #expect(W3CPropagation.extract(from: request) == nil)
  }
}

@Suite("IDGen non-zero guard")
struct IDGenTests {

  @Test("traceID is 32 hex chars and never all-zero")
  func traceIDNonZero() {
    for _ in 0..<1000 {
      let id = IDGen.traceID()
      #expect(id.count == 32)
      #expect(id != String(repeating: "0", count: 32))
    }
  }

  @Test("spanID is 16 hex chars and never all-zero")
  func spanIDNonZero() {
    for _ in 0..<1000 {
      let id = IDGen.spanID()
      #expect(id.count == 16)
      #expect(id != String(repeating: "0", count: 16))
    }
  }
}
