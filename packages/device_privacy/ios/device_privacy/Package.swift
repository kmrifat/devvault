// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "device_privacy",
  platforms: [
    .iOS("15.0")
  ],
  products: [
    .library(name: "device-privacy", targets: ["device_privacy"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "device_privacy",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ]
    )
  ]
)
