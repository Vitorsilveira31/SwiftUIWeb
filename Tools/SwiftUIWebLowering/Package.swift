// swift-tools-version: 6.2
import PackageDescription

// The Swift source lowerer. It has its own package so the framework package never depends on swift-syntax.
let package = Package(
  name: "SwiftUIWebLowering",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "swiftuiweb-lowering", targets: ["swiftuiweb-lowering"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
  ],
  targets: [
    .target(
      name: "LoweringCore",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .executableTarget(name: "swiftuiweb-lowering", dependencies: ["LoweringCore"]),
    .testTarget(name: "LoweringCoreTests", dependencies: ["LoweringCore"]),
  ]
)
