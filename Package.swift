// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "platform-swift",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(name: "DurationWire", targets: ["DurationWire"]),
    .library(name: "Observability", targets: ["Observability"]),
    .library(name: "ObservabilityLog", targets: ["ObservabilityLog"]),
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
    .library(name: "Secrets", targets: ["Secrets"]),
    .library(name: "Cache", targets: ["Cache"]),
    .library(name: "RateLimiting", targets: ["RateLimiting"]),
    .library(name: "Files", targets: ["Files"]),
    .library(name: "Fake", targets: ["Fake"]),
    .library(name: "Embeddings", targets: ["Embeddings"]),
    .library(name: "Uploads", targets: ["Uploads"]),
    .library(name: "HealthCheck", targets: ["HealthCheck"]),
    .library(name: "Panicking", targets: ["Panicking"]),
    .library(name: "Search", targets: ["Search"]),
    .library(name: "Database", targets: ["Database"]),
    .library(name: "TestSupport", targets: ["TestSupport"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    .package(url: "https://github.com/apple/swift-metrics.git", from: "2.5.0"),
  ],
  targets: [
    .target(
      name: "DurationWire",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Observability",
      dependencies: [
        .product(name: "Metrics", package: "swift-metrics")
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
      dependencies: ["DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "RetryTests",
      dependencies: ["Retry", "DurationWire"],
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
      dependencies: ["Observability", "Retry", "CircuitBreaking", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "HTTPClientTests",
      dependencies: ["HTTPClient", "Observability", "Retry", "CircuitBreaking", "DurationWire"],
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
      dependencies: ["DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "CookiesTests",
      dependencies: ["Cookies", "DurationWire"],
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
      dependencies: ["CircuitBreaking", "Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "AnalyticsTests",
      dependencies: ["Analytics"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "FeatureFlags",
      dependencies: ["CircuitBreaking", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "FeatureFlagsTests",
      dependencies: ["FeatureFlags", "CircuitBreaking", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "EventStream",
      dependencies: ["Observability", "Retry", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "EventStreamTests",
      dependencies: ["EventStream", "Observability", "Retry", "DurationWire"],
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
      dependencies: ["Observability", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "LLMTests",
      dependencies: ["LLM", "Observability", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Secrets",
      dependencies: ["Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "SecretsTests",
      dependencies: ["Secrets", "Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Cache",
      dependencies: ["Observability", "CircuitBreaking", "Encoding", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "CacheTests",
      dependencies: ["Cache", "Observability", "CircuitBreaking", "Encoding", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "RateLimiting",
      dependencies: ["Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "RateLimitingTests",
      dependencies: ["RateLimiting", "Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Files",
      dependencies: ["Encoding"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "FilesTests",
      dependencies: ["Files", "Encoding"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Fake",
      dependencies: ["RandomKit", "Identifiers"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "FakeTests",
      dependencies: ["Fake", "RandomKit", "Identifiers"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Embeddings",
      dependencies: ["HTTPClient", "Observability", "CircuitBreaking", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "EmbeddingsTests",
      dependencies: [
        "Embeddings", "HTTPClient", "Observability", "CircuitBreaking", "DurationWire",
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Uploads",
      dependencies: ["HTTPClient", "CircuitBreaking"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "UploadsTests",
      dependencies: ["Uploads", "HTTPClient", "CircuitBreaking"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "HealthCheck",
      dependencies: ["Observability", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "HealthCheckTests",
      dependencies: ["HealthCheck", "Observability", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Panicking",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "PanickingTests",
      dependencies: ["Panicking"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Search",
      dependencies: ["Embeddings", "Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)],
      linkerSettings: [.linkedLibrary("sqlite3")]
    ),
    .testTarget(
      name: "SearchTests",
      dependencies: ["Search", "Embeddings", "Observability"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Database",
      dependencies: ["Observability", "Filtering", "DurationWire"],
      swiftSettings: [.swiftLanguageMode(.v6)],
      linkerSettings: [.linkedLibrary("sqlite3")]
    ),
    .testTarget(
      name: "DatabaseTests",
      dependencies: ["Database", "Observability", "Filtering"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "TestSupport",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "TestSupportTests",
      dependencies: ["TestSupport"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
