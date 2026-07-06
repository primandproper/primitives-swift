/// # Embeddings
///
/// Ported from platform-go's `embeddings` package (`embeddings.go` + `openai/`, `ollama/`, `cohere/`,
/// `noop/`, `mock/`, `config/`) — the client-relevant slice, per the iOS-only scope of this port (see
/// `PORTING.md`).
///
/// ## What the Go package does, and how this differs
///
/// Go exposes a single-method ``Embedder`` (`GenerateEmbedding(ctx, *Input) (*Embedding, error)`) over
/// three server-callable backends — OpenAI, Ollama (a self-hosted inference server), and Cohere — plus a
/// `noop` default and a moq-generated mock. `Input` carries `{Content, Model}`; `Embedding` carries the
/// vector plus provenance (`SourceText`, `Model`, `Provider`, `Dimensions`, `GeneratedAt`).
///
/// This port simplifies the seam to what a mobile caller (and the sibling `Search` module, PORT-08,
/// which consumes this seam directly) actually needs: ``Embedder/embed(_:)`` takes a `String` and returns
/// a bare `[Float]` vector — no provenance struct, no per-call model override. ``Embedder/dimensions``
/// promotes `Embedding.Dimensions` from a per-call, response-derived field to a fixed, synchronously
/// readable property of the embedder instance itself, so a caller (e.g. Search building a vector index)
/// knows the vector width up front without awaiting a call. A default batch overload of
/// ``Embedder/embed(_:)`` (looping the single-item call) is added as a convenience Go's interface never
/// had — Go callers embed one document at a time too, so the default sequential loop is not a behavioral
/// gap, just less boilerplate for a caller embedding many chunks.
///
/// **Backends kept vs. dropped.** Per the settled port architecture (thin/native/no-dependency, drop
/// server backends that have no iOS analogue), Go's Ollama (a self-hosted HTTP server meant to run
/// alongside a backend deployment) and Cohere (another cloud REST API, offering nothing OpenAI's kept
/// backend doesn't already demonstrate) are **dropped** — there is no iOS-native reason to carry three
/// near-identical HTTP client implementations when one (OpenAI) fully exercises the pattern. What ships
/// instead:
///   * ``OnDeviceEmbedder`` — a **new**, iOS-native backend with no Go counterpart, wrapping
///     `NaturalLanguage`'s `NLEmbedding.sentenceEmbedding(for:)`. Free, offline, and synchronous, it is
///     the natural default embedder for a mobile app (no network, no API key) — see its own doc comment
///     for why `NLEmbedding` was chosen over `NLContextualEmbedding`.
///   * ``OpenAIEmbedder`` — a **live** adapter (`URLSession` via ``HTTPClient``) mirroring
///     `Sources/LLM`'s `OpenAIProvider` pattern exactly: the same request/response `Codable` shape, the
///     same `openai_embeddings_requests`/`_errors`/`_latency_ms` metric-naming convention, the same
///     ``EmbeddingsError`` status-classification table, and the same no-internal-retry contract (a 429
///     surfaces as ``EmbeddingsError/rateLimit(retryAfter:)`` for the caller to back off on). Unlike LLM,
///     this backend also threads a `CircuitBreaking.CircuitBreakerConfig` through
///     ``OpenAIEmbedderConfig`` — wrapping every request in a live circuit breaker via ``HTTPClient`` —
///     the settled rule for remote-backed modules. Go's embeddings config carries no such field, so this
///     is a deliberate port-side hardening, not a literal translation.
///   * ``NoopEmbedder`` and actor ``EmbedderMock`` — the no-op default and test double, ported from Go's
///     `noop`/`mock` packages.
///   * ``EmbeddingsConfig`` — the wire-compatible `Codable` config tree (Go's `env:` tags dropped per the
///     settled architecture; JSON keys preserved) plus ``EmbeddingsConfig/provideEmbedder(pillars:)``, the
///     provider selector. An empty/unrecognized ``EmbeddingsConfig/provider`` resolves to ``NoopEmbedder``,
///     matching Go's `ProvideEmbedder` `default` case.
///
/// Dropped (server-side / no iOS analogue): the `samber/do` DI registration (`config/do.go`) — replaced
/// everywhere in this port by plain constructor injection.
public enum Embeddings {}
