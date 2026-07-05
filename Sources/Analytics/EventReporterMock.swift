/// A test double for ``EventReporter``, ported from platform-go's moq-generated
/// `analyticsmock.EventReporterMock` (`mock/event_reporter_mock.go`).
///
/// Go's moq output is a struct of `*Func` fields (one per method) plus mutex-guarded call-recording
/// slices; calling a method whose `*Func` is unset panics ("method is nil but ... was just called"),
/// forcing every test to stub exactly what it exercises. The Swift port keeps the same shape — an
/// optional handler closure per method, plus a recorded-calls list — but trades the panic-on-unset
/// convention for a quieter default: an unset handler is simply a no-op. Thread safety comes from this
/// being an `actor` rather than from hand-rolled locks.
public actor EventReporterMock: EventReporter {
  public struct AddUserCall: Sendable, Equatable {
    public let userID: String
    public let properties: [String: AnalyticsPropertyValue]
  }

  public struct EventOccurredCall: Sendable, Equatable {
    public let event: String
    public let userID: String
    public let properties: [String: AnalyticsPropertyValue]
  }

  public struct EventOccurredAnonymousCall: Sendable, Equatable {
    public let event: String
    public let anonymousID: String
    public let properties: [String: AnalyticsPropertyValue]
  }

  public var closeHandler: (@Sendable () -> Void)?
  public var addUserHandler: (@Sendable (String, [String: AnalyticsPropertyValue]) throws -> Void)?
  public var eventOccurredHandler:
    (@Sendable (String, String, [String: AnalyticsPropertyValue]) throws -> Void)?
  public var eventOccurredAnonymousHandler:
    (@Sendable (String, String, [String: AnalyticsPropertyValue]) throws -> Void)?

  public private(set) var closeCallCount = 0
  public private(set) var addUserCalls: [AddUserCall] = []
  public private(set) var eventOccurredCalls: [EventOccurredCall] = []
  public private(set) var eventOccurredAnonymousCalls: [EventOccurredAnonymousCall] = []

  public init(
    closeHandler: (@Sendable () -> Void)? = nil,
    addUserHandler: (@Sendable (String, [String: AnalyticsPropertyValue]) throws -> Void)? = nil,
    eventOccurredHandler: (@Sendable (String, String, [String: AnalyticsPropertyValue]) throws -> Void)? =
      nil,
    eventOccurredAnonymousHandler: (
      @Sendable (String, String, [String: AnalyticsPropertyValue]) throws -> Void
    )? = nil
  ) {
    self.closeHandler = closeHandler
    self.addUserHandler = addUserHandler
    self.eventOccurredHandler = eventOccurredHandler
    self.eventOccurredAnonymousHandler = eventOccurredAnonymousHandler
  }

  public func close() {
    closeCallCount += 1
    closeHandler?()
  }

  public func addUser(userID: String, properties: [String: AnalyticsPropertyValue]) throws {
    addUserCalls.append(AddUserCall(userID: userID, properties: properties))
    try addUserHandler?(userID, properties)
  }

  public func eventOccurred(
    event: String, userID: String, properties: [String: AnalyticsPropertyValue]
  ) throws {
    eventOccurredCalls.append(EventOccurredCall(event: event, userID: userID, properties: properties))
    try eventOccurredHandler?(event, userID, properties)
  }

  public func eventOccurredAnonymous(
    event: String, anonymousID: String, properties: [String: AnalyticsPropertyValue]
  ) throws {
    eventOccurredAnonymousCalls.append(
      EventOccurredAnonymousCall(event: event, anonymousID: anonymousID, properties: properties))
    try eventOccurredAnonymousHandler?(event, anonymousID, properties)
  }
}
