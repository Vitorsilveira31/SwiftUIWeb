// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "SwiftUIWebBlocklyInterop",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "BlocklyInteropApp", targets: ["BlocklyInteropApp"])
  ],
  dependencies: [.package(path: "../..")],
  targets: [
    .executableTarget(
      name: "BlocklyInteropApp",
      dependencies: [
        .product(name: "SwiftUIWeb", package: "swiftuiweb"),
        .product(name: "SwiftUIWebBrowser", package: "swiftuiweb"),
        .product(name: "SwiftUIWebWeb", package: "swiftuiweb")
      ],
      path: "Sources",
      swiftSettings: [.swiftLanguageMode(.v5)]
    )
  ]
)
