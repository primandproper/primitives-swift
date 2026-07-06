// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "platform-swift",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(name: "Observability", targets: ["Observability"]),
    .library(name: "ObservabilityLog", targets: ["ObservabilityLog"]),
    .library(name: "ObservabilityOTel", targets: ["ObservabilityOTel"]),
    .library(name: "Filtering", targets: ["Filtering"]),
    .library(name: "APIErrors", targets: ["APIErrors"]),
    .library(name: "Retry", targets: ["Retry"]),
    .library(name: "Identifiers", targets: ["Identifiers"]),
    .library(name: "RandomKit", targets: ["RandomKit"]),
    .library(name: "Numbers", targets: ["Numbers"]),
    .library(name: "Bitmask", targets: ["Bitmask"]),
    .library(name: "Cryptography", targets: ["Cryptography"]),
    .library(name: "CircuitBreaking", targets: ["CircuitBreaking"]),
    .library(name: "HTTPClient", targets: ["HTTPClient"]),
    .library(name: "Version", targets: ["Version"]),
    .library(name: "CompressionKit", targets: ["CompressionKit"]),
    .library(name: "Cookies", targets: ["Cookies"]),
    .library(name: "QRCodes", targets: ["QRCodes"]),
    .library(name: "Encoding", targets: ["Encoding"]),
    .library(name: "Authentication", targets: ["Authentication"]),
    .library(name: "Analytics", targets: ["Analytics"]),
    .library(name: "FeatureFlags", targets: ["FeatureFlags"]),
    .library(name: "EventStream", targets: ["EventStream"]),
    .library(name: "Notifications", targets: ["Notifications"]),
    .library(name: "Capitalism", targets: ["Capitalism"]),
    .library(name: "LLM", targets: ["LLM"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    .package(url: "https://github.com/apple/swift-metrics.git", from: "2.5.0"),
  ],
  targets: [
    .target(
      name: "Observability",
      dependencies: [
        .product(name: "Metrics", package: "swift-metrics"),
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "ObservabilityLog",
      dependencies: [
        "Observability",
        .product(name: "Logging", package: "swift-log"),
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "ObservabilityOTel",
      dependencies: ["Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "ObservabilityTests",
      dependencies: ["Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "ObservabilityLogTests",
      dependencies: ["ObservabilityLog", "Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Filtering",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "APIErrors",
      dependencies: ["Filtering"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "FilteringTests",
      dependencies: ["Filtering"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "APIErrorsTests",
      dependencies: ["APIErrors", "Filtering"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Retry",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "RetryTests",
      dependencies: ["Retry"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Identifiers",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "IdentifiersTests",
      dependencies: ["Identifiers"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "RandomKit",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "RandomKitTests",
      dependencies: ["RandomKit"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Numbers",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "NumbersTests",
      dependencies: ["Numbers"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Bitmask",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "BitmaskTests",
      dependencies: ["Bitmask"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Cryptography",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "CryptographyTests",
      dependencies: ["Cryptography"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "CircuitBreaking",
      dependencies: ["Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "CircuitBreakingTests",
      dependencies: ["CircuitBreaking"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "HTTPClient",
      dependencies: ["Observability", "Retry", "CircuitBreaking"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "HTTPClientTests",
      dependencies: ["HTTPClient", "Observability", "Retry", "CircuitBreaking"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Version",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "VersionTests",
      dependencies: ["Version"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "CompressionKit",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "CompressionKitTests",
      dependencies: ["CompressionKit"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Cookies",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "CookiesTests",
      dependencies: ["Cookies"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "QRCodes",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "QRCodesTests",
      dependencies: ["QRCodes"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Encoding",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "EncodingTests",
      dependencies: ["Encoding"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Authentication",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "AuthenticationTests",
      dependencies: ["Authentication"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Analytics",
      dependencies: ["CircuitBreaking"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "AnalyticsTests",
      dependencies: ["Analytics"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "FeatureFlags",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "FeatureFlagsTests",
      dependencies: ["FeatureFlags"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "EventStream",
      dependencies: ["Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "EventStreamTests",
      dependencies: ["EventStream", "Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Notifications",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "NotificationsTests",
      dependencies: ["Notifications"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Capitalism",
      dependencies: ["Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "CapitalismTests",
      dependencies: ["Capitalism", "Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "LLM",
      dependencies: ["Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "LLMTests",
      dependencies: ["LLM", "Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
