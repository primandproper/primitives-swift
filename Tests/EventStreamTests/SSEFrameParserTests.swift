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
    #expect(dispatched.map { String(decoding: $0.payload ?? Data(), as: UTF8.self) } == [
      "\"first\"", "\"second\"", "\"third\"",
    ])
  }

  @Test("a comment line is ignored")
  func commentLineIgnored() {
    let events = parse([": keep-alive", "event: ping", "data: {}", ""])

    #expect(events.count == 1)
    #expect(events[0].type == "ping")
  }

  @Test("id and retry fields are consumed but not modeled by Event")
  func idAndRetryFieldsIgnored() {
    let events = parse(["id: 42", "retry: 3000", "event: tick", "data: {}", ""])

    #expect(events.count == 1)
    #expect(events[0].type == "tick")
    #expect(events[0].payload == Data("{}".utf8))
  }

  @Test("a blank line with no accumulated fields dispatches nothing")
  func blankLineWithNoFieldsDispatchesNothing() {
    let events = parse(["", "", "event: real", "data: {}", ""])

    #expect(events.count == 1)
    #expect(events[0].type == "real")
  }

  @Test("an event with only a type field and no data has a nil payload")
  func typeOnlyEventHasNilPayload() {
    let events = parse(["event: heartbeat", ""])

    #expect(events.count == 1)
    #expect(events[0].type == "heartbeat")
    #expect(events[0].payload == nil)
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
