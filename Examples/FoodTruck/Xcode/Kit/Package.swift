// swift-tools-version: 6.0
import PackageDescription

// FoodTruckKit as Apple's SwiftUI builds it for iOS and iPadOS. Sources/FoodTruckKit is a symlink to
// ../../../Sources/FoodTruckKit, the same files the browser build compiles; WebAdapters/ is the browser's own.
let package = Package(
  name: "FoodTruckKit",
  defaultLocalization: "en",
  platforms: [.iOS("17.0")],
  products: [.library(name: "FoodTruckKit", targets: ["FoodTruckKit"])],
  targets: [
    .target(
      name: "FoodTruckKit",
      path: "Sources",
      exclude: ["FoodTruckKit/WebAdapters"],
      resources: [
        .process("FoodTruckKit/Assets.xcassets"),
        .process("FoodTruckKit/Resources")
      ],
      swiftSettings: [.swiftLanguageMode(.v5)]
    )
  ]
)
