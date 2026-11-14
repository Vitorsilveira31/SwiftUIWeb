// swift-tools-version: 6.4
import PackageDescription

// Values an application can receive from the network, run in the Embedded (wasm32) build, where `Int` is 32 bits.
// Tools/test-hostile-values-browser.mjs presses each button in a fresh page: none may trap the app.
let aliases = [
  "SwiftUI=SwiftUIWeb",
  "Charts=SwiftUIWebCharts",
  "AVFoundation=SwiftUIWebAVFoundation",
  "Foundation=WebFoundation"
]
let aliasFlags = aliases.flatMap { ["-module-alias", $0] }

let package = Package(
  name: "HostileValues",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "HostileValues", targets: ["HostileValues"])],
  dependencies: [.package(path: "../..")],
  targets: [
    .executableTarget(
      name: "HostileValues",
      dependencies: [
        .product(name: "SwiftUIWeb", package: "swiftuiweb"),
        .product(name: "SwiftUIWebBrowser", package: "swiftuiweb"),
        .product(name: "SwiftUIWebCharts", package: "swiftuiweb"),
        .product(name: "SwiftUIWebAVFoundation", package: "swiftuiweb"),
        .product(name: "WebFoundation", package: "swiftuiweb")
      ],
      path: "Sources/HostileValues",
      swiftSettings: [.unsafeFlags(aliasFlags), .swiftLanguageMode(.v5)]
    )
  ]
)
