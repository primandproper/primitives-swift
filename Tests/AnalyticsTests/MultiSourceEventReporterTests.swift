import Testing

@testable import Analytics

@Suite("MultiSourceEventReporter routing")
struct MultiSourceEventReporterRoutingTests {
  @Test("trackEvent delegates to the source's reporter with the source property attached")
  func trackEventDelegates() async throws {
    let mock = EventReporterMock()
    let multi = MultiSourceEventReporter(reporters: ["ios": mock])

    try await multi.trackEvent(source: "ios", event: "signed_up", userID: "user123", properties: ["plan": "pro"])

    let calls = await mock.eventOccurredCalls
    #expect(calls.count == 1)
    #expect(calls[0].event == "signed_up")
    #expect(calls[0].userID == "user123")
    #expect(calls[0].properties["plan"] == "pro")
    #expect(calls[0].properties["source"] == "ios")
  }

  @Test("addUser delegates to the source's reporter with the source property attached")
  func addUserDelegates() async throws {
    let mock = EventReporterMock()
    let multi = MultiSourceEventReporter(reporters: ["web": mock])

    try await multi.addUser(source: "web", userID: "user123", properties: ["plan": "pro"])

    let calls = await mock.addUserCalls
    #expect(calls.count == 1)
    #expect(calls[0].userID == "user123")
    #expect(calls[0].properties["source"] == "web")
  }

  @Test("trackAnonymousEvent delegates to the source's reporter with the source property attached")
  func trackAnonymousEventDelegates() async throws {
    let mock = EventReporterMock()
    let multi = MultiSourceEventReporter(reporters: ["ios": mock])

    try await multi.trackAnonymousEvent(source: "ios", event: "viewed_page", anonymousID: "anon123")

    let calls = await mock.eventOccurredAnonymousCalls
    #expect(calls.count == 1)
    #expect(calls[0].anonymousID == "anon123")
    #expect(calls[0].properties["source"] == "ios")
  }

  @Test("an unknown source falls back to a working noop reporter rather than throwing")
  func unknownSourceFallsBackToNoop() async throws {
    let multi = MultiSourceEventReporter(reporters: [:])
    try await multi.trackEvent(source: "android", event: "e", userID: "u")
  }

  @Test("knownSources reports the configured source names")
  func knownSources() {
    let multi = MultiSourceEventReporter(reporters: ["ios": NoopEventReporter(), "web": NoopEventReporter()])
    #expect(Set(multi.knownSources) == ["ios", "web"])
  }
}

@Suite("MultiSourceEventReporter.close")
struct MultiSourceEventReporterCloseTests {
  @Test("closes every distinct reporter")
  func closesEveryReporter() async {
    let ios = EventReporterMock()
    let web = EventReporterMock()
    let multi = MultiSourceEventReporter(reporters: ["ios": ios, "web": web])

    await multi.close()

    #expect(await ios.closeCallCount == 1)
    #expect(await web.closeCallCount == 1)
  }

  @Test("closes a reporter shared across sources exactly once")
  func closesSharedReporterOnce() async {
    let shared = EventReporterMock()
    let multi = MultiSourceEventReporter(reporters: ["ios": shared, "web": shared])

    await multi.close()

    #expect(await shared.closeCallCount == 1)
  }
}

@Suite("MultiSourceEventReporter construction from proxy sources config")
struct MultiSourceEventReporterConstructionTests {
  @Test("no proxy sources configured produces an empty, working reporter")
  func emptyProxySources() async throws {
    let multi = MultiSourceEventReporter(proxySources: [:])
    #expect(multi.knownSources.isEmpty)
    try await multi.trackEvent(source: "ios", event: "e", userID: "u")
  }

  @Test("a source whose collector fails to build falls back to noop")
  func fallsBackToNoopOnFailure() async throws {
    struct Boom: Error {}
    let multi = MultiSourceEventReporter(
      proxySources: ["ios": SourceConfig(provider: "segment")],
      makeReporter: { _ in throw Boom() })

    // Doesn't throw: the failure is swallowed and the source silently gets a noop, matching Go.
    try await multi.trackEvent(source: "ios", event: "e", userID: "u")
  }

  @Test("the default makeReporter uses SourceConfig.provideCollector, buffering without a network call")
  func defaultMakeReporterBuffersWithoutNetwork() async throws {
    let multi = MultiSourceEventReporter(
      proxySources: [
        "ios": SourceConfig(segment: SegmentConfig(apiToken: "tok"), provider: "segment")
      ])
    // provideCollector() now returns a real SegmentEventReporter; trackEvent only buffers in memory
    // (no flush without close/batch-size), so this never touches the network.
    try await multi.trackEvent(source: "ios", event: "e", userID: "u")
  }

  @Test("a source with an empty credential key falls back to noop")
  func emptyCredentialFallsBackToNoop() async throws {
    // provideCollector() throws emptyWriteKey; the source silently degrades to noop, matching Go.
    let multi = MultiSourceEventReporter(
      proxySources: [
        "ios": SourceConfig(segment: SegmentConfig(apiToken: ""), provider: "segment")
      ])
    try await multi.trackEvent(source: "ios", event: "e", userID: "u")
  }

  @Test("posthog sources sharing an API key reuse a single reporter instance")
  func deduplicatesPostHogByAPIKey() async throws {
    let shared = EventReporterMock()
    let other = EventReporterMock()

    let multi = MultiSourceEventReporter(
      proxySources: [
        "ios": SourceConfig(posthog: PostHogConfig(apiKey: "shared-key"), provider: "posthog"),
        "web": SourceConfig(posthog: PostHogConfig(apiKey: "shared-key"), provider: "posthog"),
        "third": SourceConfig(posthog: PostHogConfig(apiKey: "distinct-key"), provider: "posthog"),
      ],
      makeReporter: { config in
        config.posthog?.apiKey == "shared-key" ? shared : other
      })

    try await multi.trackEvent(source: "ios", event: "e1", userID: "u")
    try await multi.trackEvent(source: "web", event: "e2", userID: "u")
    try await multi.trackEvent(source: "third", event: "e3", userID: "u")

    #expect(await shared.eventOccurredCalls.count == 2)
    #expect(await other.eventOccurredCalls.count == 1)

    // Closing must not double-close the deduplicated shared reporter.
    await multi.close()
    #expect(await shared.closeCallCount == 1)
    #expect(await other.closeCallCount == 1)
  }

  @Test("posthog sources with distinct API keys each get their own reporter")
  func distinctPostHogKeysGetSeparateReporters() async throws {
    let first = EventReporterMock()
    let second = EventReporterMock()

    let multi = MultiSourceEventReporter(
      proxySources: [
        "ios": SourceConfig(posthog: PostHogConfig(apiKey: "key-one"), provider: "posthog"),
        "web": SourceConfig(posthog: PostHogConfig(apiKey: "key-two"), provider: "posthog"),
      ],
      makeReporter: { config in
        config.posthog?.apiKey == "key-one" ? first : second
      })

    try await multi.trackEvent(source: "ios", event: "e1", userID: "u")
    try await multi.trackEvent(source: "web", event: "e2", userID: "u")

    #expect(await first.eventOccurredCalls.count == 1)
    #expect(await second.eventOccurredCalls.count == 1)
  }
}
