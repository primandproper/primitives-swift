import Foundation

/// A test double for ``Uploader``, ported from platform-go's moq-generated `mock.UploadManagerMock`.
///
/// Go's moq output is a struct with `SaveFunc`/`OpenFunc`/… handler fields plus mutex-guarded call
/// recording; an unset handler panics. The Swift port keeps the shape — optional handler closures plus
/// recorded-call lists — but trades panic-on-unset for quiet defaults (save/delete succeed, read returns
/// empty data, exists returns `false`). Thread safety comes from being an `actor` rather than hand-rolled
/// locks, matching ``LLM/LLMProviderMock``.
///
/// The handlers are `public var` on an actor, so they can't be assigned cross-actor under Swift 6; use the
/// `set*Handler` mutators to script the double after construction (REPO-05).
public actor UploaderMock: Uploader {
  /// A recorded ``save(_:data:options:)`` call.
  public struct SaveCall: Sendable, Equatable {
    public let path: String
    public let data: Data
    public let options: SaveOptions
  }

  public var saveHandler: (@Sendable (String, Data, SaveOptions) async throws -> Void)?
  public var readHandler: (@Sendable (String) async throws -> Data)?
  public var deleteHandler: (@Sendable (String) async throws -> Void)?
  public var existsHandler: (@Sendable (String) async throws -> Bool)?

  public private(set) var saveCalls: [SaveCall] = []
  public private(set) var readCalls: [String] = []
  public private(set) var deleteCalls: [String] = []
  public private(set) var existsCalls: [String] = []

  public init(
    saveHandler: (@Sendable (String, Data, SaveOptions) async throws -> Void)? = nil,
    readHandler: (@Sendable (String) async throws -> Data)? = nil,
    deleteHandler: (@Sendable (String) async throws -> Void)? = nil,
    existsHandler: (@Sendable (String) async throws -> Bool)? = nil
  ) {
    self.saveHandler = saveHandler
    self.readHandler = readHandler
    self.deleteHandler = deleteHandler
    self.existsHandler = existsHandler
  }

  public func setSaveHandler(
    _ handler: (@Sendable (String, Data, SaveOptions) async throws -> Void)?
  ) {
    saveHandler = handler
  }

  public func setReadHandler(_ handler: (@Sendable (String) async throws -> Data)?) {
    readHandler = handler
  }

  public func setDeleteHandler(_ handler: (@Sendable (String) async throws -> Void)?) {
    deleteHandler = handler
  }

  public func setExistsHandler(_ handler: (@Sendable (String) async throws -> Bool)?) {
    existsHandler = handler
  }

  public func save(_ path: String, data: Data, options: SaveOptions) async throws {
    saveCalls.append(SaveCall(path: path, data: data, options: options))
    if let saveHandler {
      try await saveHandler(path, data, options)
    }
  }

  public func read(_ path: String) async throws -> Data {
    readCalls.append(path)
    if let readHandler {
      return try await readHandler(path)
    }
    return Data()
  }

  public func delete(_ path: String) async throws {
    deleteCalls.append(path)
    if let deleteHandler {
      try await deleteHandler(path)
    }
  }

  public func exists(_ path: String) async throws -> Bool {
    existsCalls.append(path)
    if let existsHandler {
      return try await existsHandler(path)
    }
    return false
  }
}
