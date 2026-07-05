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
    .library(name: "ObservabilityOTel", targets: ["ObservabilityOTel"]),
    .library(name: "Filtering", targets: ["Filtering"]),
    .library(name: "APIErrors", targets: ["APIErrors"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    .package(url: "https://github.com/apple/swift-metrics.git", from: "2.5.0"),
  ],
  targets: [
    .target(
      name: "Observability",
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Metrics", package: "swift-metrics"),
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
  ]
)
