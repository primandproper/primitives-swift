/// A test double for ``BatchCache``, the analogue of platform-go's moq-generated `CacheMock` /
/// `BatchCacheMock` (`cache/mock/*.go`).
///
/// Go's moq output is a struct of `*Func` fields plus mutex-guarded call recording, and panics when a
/// method's `Func` is unset. The Swift port keeps the recorded-calls idea but is friendlier: unless an
/// override handler is installed, each method runs against a real in-memory dictionary, so the mock is a
/// working cache out of the box (round-trips actually work). Optional per-method handlers override that
/// default to script misses, errors, or fixed responses.
///
/// It is an `actor` (matching ``LLMProviderMock`` / `Analytics.EventReporterMock`), so the handlers are
/// stored `var`s that can't be assigned cross-actor; the `set…Handler` mutators are the supported way to
/// script the double after construction (the REPO-05 rule).
public actor CacheMock<Value: Codable & Sendable>: BatchCache {
  // MARK: Recorded calls

  public private(set) var getCalls: [String] = []
  public private(set) var setCalls: [(key: String, value: Value)] = []
  public private(set) var deleteCalls: [String] = []
  public private(set) var getManyCalls: [[String]] = []
  public private(set) var setManyCalls: [[String: Value]] = []
  public private(set) var pingCallCount = 0

  // MARK: Optional override handlers

  private var getHandler: (@Sendable (String) async throws -> Value?)?
  private var setHandler: (@Sendable (String, Value) async throws -> Void)?
  private var deleteHandler: (@Sendable (String) async throws -> Void)?
  private var getManyHandler: (@Sendable ([String]) async throws -> [String: Value])?
  private var setManyHandler: (@Sendable ([String: Value]) async throws -> Void)?
  private var pingHandler: (@Sendable () async throws -> Void)?

  /// The default backing store used whenever a handler is not installed.
  private var store: [String: Value] = [:]

  public init() {}

  // MARK: Handler mutators (REPO-05: `var` handlers can't be set cross-actor)

  public func setGetHandler(_ handler: (@Sendable (String) async throws -> Value?)?) {
    getHandler = handler
  }
  public func setSetHandler(_ handler: (@Sendable (String, Value) async throws -> Void)?) {
    setHandler = handler
  }
  public func setDeleteHandler(_ handler: (@Sendable (String) async throws -> Void)?) {
    deleteHandler = handler
  }
  public func setGetManyHandler(
    _ handler: (@Sendable ([String]) async throws -> [String: Value])?
  ) {
    getManyHandler = handler
  }
  public func setSetManyHandler(_ handler: (@Sendable ([String: Value]) async throws -> Void)?) {
    setManyHandler = handler
  }
  public func setPingHandler(_ handler: (@Sendable () async throws -> Void)?) {
    pingHandler = handler
  }

  // MARK: BatchCache

  public func get(_ key: String) async throws -> Value? {
    getCalls.append(key)
    if let getHandler { return try await getHandler(key) }
    return store[key]
  }

  public func set(_ key: String, to value: Value) async throws {
    setCalls.append((key: key, value: value))
    if let setHandler {
      try await setHandler(key, value)
      return
    }
    store[key] = value
  }

  public func delete(_ key: String) async throws {
    deleteCalls.append(key)
    if let deleteHandler {
      try await deleteHandler(key)
      return
    }
    store[key] = nil
  }

  public func getMany(_ keys: [String]) async throws -> [String: Value] {
    getManyCalls.append(keys)
    if let getManyHandler { return try await getManyHandler(keys) }
    var out: [String: Value] = [:]
    for key in keys where store[key] != nil {
      out[key] = store[key]
    }
    return out
  }

  public func setMany(_ items: [String: Value]) async throws {
    setManyCalls.append(items)
    if let setManyHandler {
      try await setManyHandler(items)
      return
    }
    for (key, value) in items {
      store[key] = value
    }
  }

  public func ping() async throws {
    pingCallCount += 1
    if let pingHandler { try await pingHandler() }
  }
}
