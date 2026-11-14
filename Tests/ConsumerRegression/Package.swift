// swift-tools-version: 6.4
import PackageDescription

// Consumer regression probe: an application that imports Apple's frameworks by name and builds for the Embedded
// browser through SwiftUIWeb's launcher. Exercises the surfaces fixed by the JSON, unit, calendar, predicate, regex,
// URLSession and shape-paint work.
let aliases = [
  "SwiftUI=SwiftUIWeb",
  "Foundation=WebFoundation"
]
let aliasFlags = aliases.flatMap { ["-module-alias", $0] }

let package = Package(
  name: "ConsumerRegression",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "ConsumerRegression", targets: ["ConsumerRegression"])],
  dependencies: [.package(path: "../..")],
  targets: [
    .executableTarget(
      name: "ConsumerRegression",
      dependencies: [
        .product(name: "SwiftUIWeb", package: "swiftuiweb"),
        .product(name: "SwiftUIWebBrowser", package: "swiftuiweb"),
        .product(name: "WebFoundation", package: "swiftuiweb")
      ],
      path: "Sources/ConsumerRegression",
      swiftSettings: [.unsafeFlags(aliasFlags), .swiftLanguageMode(.v5)]
    )
  ]
)
