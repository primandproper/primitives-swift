import os

/// A recording test double for ``QRCodeBuilder`` (REPO-05, QRCodes slice). Where ``NoopQRCodeBuilder``
/// is the silent DI default, this mock *records* every call and lets a test script the return, the
/// analogue of platform-go's moq-generated `qrcodesmock.BuilderMock` (a `BuildQRCodeFunc` field plus
/// mutex-guarded call recording).
///
/// ``QRCodeBuilder/buildQRCode(username:twoFactorSecret:)`` is a **synchronous** `throws(QRCodeError)`
/// method, so this can't be an `actor` (its methods would have to be `async`). It is instead a
/// `final class` whose state is guarded by an `OSAllocatedUnfairLock`, the same `@unchecked Sendable`
/// recording pattern `Observability`'s `RecordingObserver` uses.
///
/// The scripted outcome is a `@Sendable (username, secret) -> Result<String, QRCodeError>` closure
/// rather than a typed-throws closure: a stored `throws(QRCodeError)` closure type would raise the
/// module's deployment floor to macOS 15, so the mock unwraps the `Result` and rethrows itself,
/// preserving the typed-throws surface without the newer-OS requirement. An unset handler returns
/// empty content, matching the quiet default the ``LLMProviderMock`` chose over moq's panic-on-unset.
public final class MockQRCodeBuilder: QRCodeBuilder, @unchecked Sendable {
  /// One recorded invocation, captured in call order.
  public struct Call: Sendable, Equatable {
    public let username: String
    public let twoFactorSecret: String
  }

  private struct State {
    var handler: (@Sendable (String, String) -> Result<String, QRCodeError>)?
    var calls: [Call] = []
  }
  private let state = OSAllocatedUnfairLock(initialState: State())

  public init(handler: (@Sendable (String, String) -> Result<String, QRCodeError>)? = nil) {
    state.withLock { $0.handler = handler }
  }

  /// (Re)configures the scripted outcome after construction.
  public func setHandler(_ handler: (@Sendable (String, String) -> Result<String, QRCodeError>)?) {
    state.withLock { $0.handler = handler }
  }

  /// The calls seen so far, in order.
  public var calls: [Call] { state.withLock { $0.calls } }

  /// The number of times ``buildQRCode(username:twoFactorSecret:)`` was invoked.
  public var callCount: Int { state.withLock { $0.calls.count } }

  public func buildQRCode(
    username: String, twoFactorSecret: String
  ) throws(QRCodeError) -> String {
    let handler = state.withLock {
      (state) -> (@Sendable (String, String) -> Result<String, QRCodeError>)? in
      state.calls.append(Call(username: username, twoFactorSecret: twoFactorSecret))
      return state.handler
    }
    guard let handler else { return "" }
    switch handler(username, twoFactorSecret) {
    case .success(let value): return value
    case .failure(let error): throw error
    }
  }
}
