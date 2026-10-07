// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "biometric_key",
  platforms: [
    .iOS("15.0"),
    .macOS("12.0"),
  ],
  products: [
    .library(name: "biometric-key", targets: ["biometric_key"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "biometric_key",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ]
    )
  ]
)
