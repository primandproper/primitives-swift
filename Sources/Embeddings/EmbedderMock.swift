/// A test double for ``Embedder``, ported from platform-go's moq-generated `embeddingsmock.EmbedderMock`
/// (`mock/embedder_mock.go`).
///
/// Go's moq output is a struct with a `GenerateEmbeddingFunc` field plus mutex-guarded call recording;
/// calling a method whose `*Func` is unset panics. The Swift port keeps the shape — an optional handler
/// closure plus a recorded-calls list — but trades panic-on-unset for a quieter default: an unset handler
/// returns an empty vector, mirroring ``NoopEmbedder``. Thread safety comes from this being an `actor`
/// rather than hand-rolled locks, matching `Sources/LLM`'s `LLMProviderMock`.
///
/// ``dimensions`` is `nonisolated let` rather than actor-isolated state: it is fixed at construction (a
/// test configures the mock's vector width once, up front) and the ``Embedder`` protocol's `dimensions`
/// requirement is a synchronous, non-`async` property — an actor can only satisfy that with a
/// `nonisolated` member, the same move `EventStream`'s `MockEventStream.events` makes for its own
/// synchronous protocol requirement.
public actor EmbedderMock: Embedder {
  public nonisolated let dimensions: Int

  public var embedHandler: (@Sendable (String) async throws -> [Float])?

  public private(set) var embedCalls: [String] = []

  public init(
    dimensions: Int = 0,
    embedHandler: (@Sendable (String) async throws -> [Float])? = nil
  ) {
    self.dimensions = dimensions
    self.embedHandler = embedHandler
  }

  /// (Re)configures the handler after construction. `embedHandler` is a `public var` on an actor, so it
  /// can't be assigned from outside (`mock.embedHandler = …` is rejected under Swift 6 actor isolation);
  /// this async mutator is the supported way to script the double post-init (REPO-05).
  public func setEmbedHandler(_ handler: (@Sendable (String) async throws -> [Float])?) {
    embedHandler = handler
  }

  public func embed(_ text: String) async throws -> [Float] {
    embedCalls.append(text)
    if let embedHandler {
      return try await embedHandler(text)
    }
    return []
  }
}
