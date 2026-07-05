import Foundation
import os

/// A test double for ``PurchaseManager``, ported from platform-go's moq-generated
/// `capitalismmock.PaymentManagerMock` (`mock/payment_manager_mock.go`) — but reshaped to the client
/// interface and following the same conventions as ``Analytics``'s `EventReporterMock`.
///
/// Go's moq output is a struct of `*Func` fields plus mutex-guarded call-recording slices, where an
/// unset `*Func` panics. This port keeps the shape — one handler closure per method plus a recorded-
/// calls list — but trades panic-on-unset for a quiet default (an unset handler returns the empty/
/// neutral value), and gets thread safety from being an `actor`.
///
/// One method breaks the actor mold: ``transactionUpdates()`` is a *synchronous* protocol requirement,
/// which on an actor must be `nonisolated` and so cannot read actor-isolated state. Its handler is
/// therefore an immutable, `nonisolated` (`Sendable`) closure fixed at init, and its call count lives
/// behind a lock rather than in actor storage.
public actor PurchaseManagerMock: PurchaseManager {
  public struct PurchaseCall: Sendable, Equatable {
    public let productID: String
    public let options: PurchaseOptions
  }

  public var productsHandler: (@Sendable ([String]) throws -> [PurchaseProduct])?
  public var purchaseHandler: (@Sendable (String, PurchaseOptions) throws -> PurchaseResult)?
  public var currentEntitlementsHandler: (@Sendable () -> [Entitlement])?
  public var restorePurchasesHandler: (@Sendable () throws -> Void)?

  public private(set) var productsCalls: [[String]] = []
  public private(set) var purchaseCalls: [PurchaseCall] = []
  public private(set) var currentEntitlementsCallCount = 0
  public private(set) var restorePurchasesCallCount = 0

  private nonisolated let transactionUpdatesHandler:
    (@Sendable () -> AsyncStream<TransactionUpdate>)?
  private nonisolated let transactionUpdatesCallCountLock = OSAllocatedUnfairLock(initialState: 0)

  /// How many times ``transactionUpdates()`` has been called. `nonisolated` (lock-backed) to match the
  /// method, so it reads without hopping onto the actor.
  public nonisolated var transactionUpdatesCallCount: Int {
    transactionUpdatesCallCountLock.withLock { $0 }
  }

  public init(
    productsHandler: (@Sendable ([String]) throws -> [PurchaseProduct])? = nil,
    purchaseHandler: (@Sendable (String, PurchaseOptions) throws -> PurchaseResult)? = nil,
    currentEntitlementsHandler: (@Sendable () -> [Entitlement])? = nil,
    restorePurchasesHandler: (@Sendable () throws -> Void)? = nil,
    transactionUpdatesHandler: (@Sendable () -> AsyncStream<TransactionUpdate>)? = nil
  ) {
    self.productsHandler = productsHandler
    self.purchaseHandler = purchaseHandler
    self.currentEntitlementsHandler = currentEntitlementsHandler
    self.restorePurchasesHandler = restorePurchasesHandler
    self.transactionUpdatesHandler = transactionUpdatesHandler
  }

  public func products(for identifiers: [String]) throws -> [PurchaseProduct] {
    productsCalls.append(identifiers)
    return try productsHandler?(identifiers) ?? []
  }

  public func purchase(productID: String, options: PurchaseOptions) throws -> PurchaseResult {
    purchaseCalls.append(PurchaseCall(productID: productID, options: options))
    return try purchaseHandler?(productID, options) ?? .userCancelled
  }

  public func currentEntitlements() -> [Entitlement] {
    currentEntitlementsCallCount += 1
    return currentEntitlementsHandler?() ?? []
  }

  public func restorePurchases() throws {
    restorePurchasesCallCount += 1
    try restorePurchasesHandler?()
  }

  public nonisolated func transactionUpdates() -> AsyncStream<TransactionUpdate> {
    transactionUpdatesCallCountLock.withLock { $0 += 1 }
    return transactionUpdatesHandler?() ?? AsyncStream { $0.finish() }
  }
}
