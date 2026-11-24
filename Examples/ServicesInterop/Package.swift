// swift-tools-version: 6.4
import PackageDescription

// A page service (`BrowserService`, "Page services" in Documentation/BROWSER_APP_SHELL.md) called from Swift: the
// browser check Tools/test-services-browser.mjs runs it on the main thread and in a worker.
let package = Package(
  name: "SwiftUIWebServicesInterop",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "ServicesInteropApp", targets: ["ServicesInteropApp"])
  ],
  dependencies: [.package(path: "../..")],
  targets: [
    .executableTarget(
      name: "ServicesInteropApp",
      dependencies: [
        .product(name: "SwiftUIWeb", package: "swiftuiweb"),
        .product(name: "SwiftUIWebBrowser", package: "swiftuiweb"),
        .product(name: "SwiftUIWebBrowserIO", package: "swiftuiweb")
      ],
      path: "Sources",
      swiftSettings: [.swiftLanguageMode(.v5)]
    )
  ]
)
