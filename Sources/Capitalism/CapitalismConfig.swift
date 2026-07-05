import Foundation
import Observability

/// The top-level payments configuration, ported from platform-go's `capitalismcfg.Config`
/// (`capitalism/config/config.go`):
/// ```go
/// type Config struct {
///   Stripe   *stripe.Config
///   Provider string
///   Enabled  bool
/// }
/// ```
/// The `Stripe` field is replaced by the two iOS-relevant provider blocks (``storeKit``,
/// ``revenueCat``); the `Provider`/`Enabled` shape and its JSON keys carry over. As in the origin, a
/// disabled config short-circuits to a noop manager and skips validation entirely.
public struct CapitalismConfig: Codable, Sendable, Equatable {
  /// The raw provider string, e.g. `"storekit"`/`"revenuecat"`. Kept as a raw `String` (not
  /// ``CapitalismProvider``) so an empty/unrecognized value resolves leniently — matching the Go
  /// origin's `switch strings.ToLower(cfg.Provider)`. See ``resolvedProvider``.
  public var provider: String
  /// Whether payments are enabled. When `false`, ``provideManager(observer:)`` returns a
  /// ``NoopPurchaseManager`` and ``validate()`` is a no-op — mirrors Go's `if !cfg.Enabled`.
  public var enabled: Bool
  public var storeKit: StoreKitConfig?
  public var revenueCat: RevenueCatConfig?

  public init(
    provider: String = "",
    enabled: Bool = false,
    storeKit: StoreKitConfig? = nil,
    revenueCat: RevenueCatConfig? = nil
  ) {
    self.provider = provider
    self.enabled = enabled
    self.storeKit = storeKit
    self.revenueCat = revenueCat
  }

  private enum CodingKeys: String, CodingKey {
    case provider
    case enabled
    case storeKit
    case revenueCat
  }

  /// Missing keys decode to Go's zero values rather than failing, matching how a partial JSON object
  /// unmarshals into a Go struct.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    storeKit = try container.decodeIfPresent(StoreKitConfig.self, forKey: .storeKit)
    revenueCat = try container.decodeIfPresent(RevenueCatConfig.self, forKey: .revenueCat)
  }

  /// The ``CapitalismProvider`` `provider` resolves to (trimmed, lowercased), or `nil` if empty/
  /// unrecognized — the same lenient shape ``Analytics``'s `SourceConfig.resolvedProvider` uses.
  public var resolvedProvider: CapitalismProvider? {
    CapitalismProvider(
      rawValue: provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }

  /// Validates the config, mirroring Go's `Config.ValidateWithContext`: a disabled config is always
  /// valid; an enabled one must name a recognized provider, and the RevenueCat provider additionally
  /// requires its credentials block (StoreKit needs none — App Store Connect holds everything).
  ///
  /// This is slightly stricter than the Go origin, whose `validation.In(StripeProvider)` skipped an
  /// empty provider string (leaving it to fail later at construction). Here an enabled config with an
  /// empty/unknown provider fails validation up front, since ``provideManager(observer:)`` would throw
  /// anyway.
  public func validate() throws {
    guard enabled else { return }

    guard let resolved = resolvedProvider else {
      throw CapitalismConfigError.unknownProvider(provider)
    }

    switch resolved {
    case .storeKit:
      break
    case .revenueCat:
      guard let revenueCat else {
        throw CapitalismConfigError.missingProviderConfig(.revenueCat)
      }
      do {
        try revenueCat.validate()
      } catch let error as RevenueCatConfigError {
        throw CapitalismConfigError.invalidRevenueCatConfig(error)
      }
    }
  }

  /// Builds the configured ``PurchaseManager``, ported from Go's `ProvideCapitalismImplementation`.
  ///
  /// - A disabled config returns ``NoopPurchaseManager`` (Go's `if !cfg.Enabled` short-circuit).
  /// - An empty/unrecognized provider throws ``CapitalismConfigError/unknownProvider(_:)`` (Go's
  ///   `default: return errors.Newf("unknown provider: %q", ...)`).
  /// - ``CapitalismProvider/storeKit`` returns a live ``StoreKitPurchaseManager``.
  /// - ``CapitalismProvider/revenueCat`` throws ``CapitalismError/unsupportedProvider(_:)`` — the
  ///   salsa20 treatment (its config must still be present, matching Go's "provider configured but
  ///   config is nil" guard).
  public func provideManager(observer: any Observer) throws -> any PurchaseManager {
    guard enabled else { return NoopPurchaseManager() }

    guard let resolved = resolvedProvider else {
      throw CapitalismConfigError.unknownProvider(provider)
    }

    switch resolved {
    case .storeKit:
      return StoreKitPurchaseManager(
        productIdentifiers: storeKit?.productIdentifiers ?? [], observer: observer)
    case .revenueCat:
      guard revenueCat != nil else {
        throw CapitalismConfigError.missingProviderConfig(.revenueCat)
      }
      throw CapitalismError.unsupportedProvider(.revenueCat)
    }
  }
}

/// A rejected ``CapitalismConfig``. Go returned an `ozzo-validation`/`errors.Newf` error; the port names
/// each concrete failure mode so a caller can branch on them.
public enum CapitalismConfigError: Error, Equatable, Sendable {
  /// The provider string was empty or not a recognized ``CapitalismProvider`` while `enabled` was true.
  case unknownProvider(String)
  /// The provider was recognized but its matching credentials block was `nil`.
  case missingProviderConfig(CapitalismProvider)
  case invalidRevenueCatConfig(RevenueCatConfigError)
}

extension CapitalismConfigError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unknownProvider(let provider):
      return "provider: must be a valid value, got \(provider.isEmpty ? "\"\"" : provider)"
    case .missingProviderConfig(let provider):
      return "\(provider.rawValue) provider configured but \(provider.rawValue) config is nil"
    case .invalidRevenueCatConfig(let error):
      return "revenueCat: \(error.localizedDescription)"
    }
  }
}
