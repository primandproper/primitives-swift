import Foundation
import Testing

@testable import EventStream

/// Feeds a sequence of raw SSE lines (as Go's `sse.sseStream.Send` would write them, one per physical
/// line with no trailing `\n`) through a fresh parser, returning the events it dispatched.
private func parse(_ lines: [String]) -> [Event] {
  var parser = SSEFrameParser()
  var events: [Event] = []
  for line in lines {
    if let event = parser.consume(line) {
      events.append(event)
    }
  }
  return events
}

@Suite("SSEFrameParser")
struct SSEFrameParserTests {
  @Test("a typed event with a single-line data field")
  func typedSingleLineEvent() {
    let events = parse(["event: test_event", "data: {\"msg\":\"hello\"}", ""])

    #expect(events.count == 1)
    #expect(events[0].type == "test_event")
    #expect(events[0].payload == Data(#"{"msg":"hello"}"#.utf8))
  }

  @Test("an event without a type field decodes to an empty type")
  func eventWithoutType() {
    let events = parse(["data: {\"x\":1}", ""])

    #expect(events.count == 1)
    #expect(events[0].type == "")
    #expect(events[0].payload == Data(#"{"x":1}"#.utf8))
  }

  @Test("multiple data lines rejoin with \\n, reconstructing the original payload")
  func multiLineDataRejoins() {
    // Mirrors Go's sender splitting a payload containing "\n" into one "data:" line per source line.
    let events = parse(["data: line1", "data: event: injected", ""])

    #expect(events.count == 1)
    #expect(events[0].type == "")
    #expect(events[0].payload == Data("line1\nevent: injected".utf8))
  }

  @Test("a data line's embedded \"event:\" text is not parsed as a new field")
  func embeddedFieldNameInDataIsNotInjected() {
    // The physical line's field name (before its own first colon) is "data", so the value "event:
    // injected" is opaque payload content, matching Go's neutralize-newlines SSE-injection test.
    let events = parse(["event: real", "data: event: injected", ""])

    #expect(events.count == 1)
    #expect(events[0].type == "real")
    #expect(events[0].payload == Data("event: injected".utf8))
  }

  @Test("multiple events separated by blank lines dispatch independently")
  func multipleEvents() {
    var parser = SSEFrameParser()
    var dispatched: [Event] = []

    for name in ["first", "second", "third"] {
      for line in ["event: msg", "data: \"\(name)\"", ""] {
        if let event = parser.consume(line) {
          dispatched.append(event)
        }
      }
    }

    #expect(dispatched.map(\.type) == ["msg", "msg", "msg"])
    #expect(
      dispatched.map { String(decoding: $0.payload ?? Data(), as: UTF8.self) } == [
        "\"first\"", "\"second\"", "\"third\"",
      ])
  }

  @Test("a comment line is ignored")
  func commentLineIgnored() {
    let events = parse([": keep-alive", "event: ping", "data: {}", ""])

    #expect(events.count == 1)
    #expect(events[0].type == "ping")
  }

  @Test("id and retry fields are retained as reconnection state, not surfaced on Event")
  func idAndRetryFieldsTrackedNotModeled() {
    var parser = SSEFrameParser()
    var events: [Event] = []
    for line in ["id: 42", "retry: 3000", "event: tick", "data: {}", ""] {
      if let event = parser.consume(line) { events.append(event) }
    }

    // The dispatched Event still models only type/payload, exactly as before.
    #expect(events.count == 1)
    #expect(events[0].type == "tick")
    #expect(events[0].payload == Data("{}".utf8))
    // But the parser now exposes the reconnection fields a reconnecting wrapper needs.
    #expect(parser.lastEventID == "42")
    #expect(parser.reconnectionTime == .milliseconds(3000))
  }

  @Test("the last event ID persists across frames until a new id arrives")
  func lastEventIDPersistsAcrossFrames() {
    var parser = SSEFrameParser()
    for line in ["id: first", "data: {}", ""] { _ = parser.consume(line) }
    #expect(parser.lastEventID == "first")

    // A frame with no id: leaves the buffer untouched (WHATWG: it is not reset between events).
    for line in ["data: {}", ""] { _ = parser.consume(line) }
    #expect(parser.lastEventID == "first")

    // A new id: overwrites it.
    for line in ["id: second", "data: {}", ""] { _ = parser.consume(line) }
    #expect(parser.lastEventID == "second")
  }

  @Test("a non-digit retry value is ignored, not honored")
  func nonDigitRetryIgnored() {
    var parser = SSEFrameParser()
    for line in ["retry: 1500", "data: {}", ""] { _ = parser.consume(line) }
    #expect(parser.reconnectionTime == .milliseconds(1500))

    // Per WHATWG, a non-ASCII-digit retry value is ignored — it must not clear the prior value.
    for line in ["retry: soon", "data: {}", ""] { _ = parser.consume(line) }
    #expect(parser.reconnectionTime == .milliseconds(1500))
  }

  @Test("a blank line with no accumulated fields dispatches nothing")
  func blankLineWithNoFieldsDispatchesNothing() {
    let events = parse(["", "", "event: real", "data: {}", ""])

    #expect(events.count == 1)
    #expect(events[0].type == "real")
  }

  @Test("a frame with no data line dispatches nothing, per the WHATWG dispatch step")
  func emptyDataFrameDispatchesNothing() {
    // A lone `event:` with no `data:` has an empty data buffer, so the spec dispatches nothing — its
    // id/retry side effects still apply, but no Event is produced.
    var parser = SSEFrameParser()
    var events: [Event] = []
    for line in ["event: heartbeat", "id: h1", ""] {
      if let event = parser.consume(line) { events.append(event) }
    }

    #expect(events.isEmpty)
    #expect(parser.lastEventID == "h1")

    // A following real frame still dispatches normally (buffers were reset, id persisted).
    for line in ["data: {}", ""] {
      if let event = parser.consume(line) { events.append(event) }
    }
    #expect(events.count == 1)
    #expect(events[0].type == "")
  }

  @Test("the exact bytes Go's sse.sseStream.Send writes for one event")
  func matchesGoWriterOutputExactly() {
    // "event: update\ndata: {\"id\":\"abc\",\"status\":\"done\"}\n\n" split into lines without terminators.
    let events = parse(["event: update", #"data: {"id":"abc","status":"done"}"#, ""])

    #expect(events.count == 1)
    #expect(events[0].type == "update")
    #expect(events[0].payload == Data(#"{"id":"abc","status":"done"}"#.utf8))
  }
}
