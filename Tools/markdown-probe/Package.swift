// swift-tools-version: 6.4
import PackageDescription

// Differential probe for `AttributedString(markdown:)` on the Embedded WASI profile. Built and run by
// Tools/test-markdown-probe.mjs; the parser only exists there, so no native test target can reach it.
let package = Package(
  name: "MarkdownProbe",
  dependencies: [
    .package(path: "../.."),
  ],
  targets: [
    .executableTarget(
      name: "MarkdownProbe",
      dependencies: [
        .product(name: "SwiftUIWebCore", package: "swiftuiweb"),
        .product(name: "SwiftUIWebFeatures", package: "swiftuiweb"),
        .product(name: "SwiftUIWebTransferable", package: "swiftuiweb"),
      ],
      swiftSettings: [.enableExperimentalFeature("Extern")],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-lswiftUnicodeDataTables"])]
    ),
  ]
)
