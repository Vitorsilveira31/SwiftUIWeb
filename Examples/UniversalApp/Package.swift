// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "UniversalAppWeb",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "UniversalWebApp", targets: ["UniversalWebApp"])
  ],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .target(
      name: "Shared",
      dependencies: [
        .product(name: "SwiftUIWeb", package: "swiftuiweb")
      ],
      path: "Sources/Shared",
      swiftSettings: [
        .define("WEB"),
        .swiftLanguageMode(.v5)
      ]
    ),
    .executableTarget(
      name: "UniversalWebApp",
      dependencies: [
        "Shared",
        .product(name: "SwiftUIWebBrowser", package: "swiftuiweb")
      ],
      path: "Web",
      swiftSettings: [.swiftLanguageMode(.v5)]
    )
  ]
)
