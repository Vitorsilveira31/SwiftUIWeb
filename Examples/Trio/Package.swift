// swift-tools-version: 6.1
import PackageDescription

// One package, one shared source tree (Sources/Trio), three platforms. The layout follows a large production app:
//  - Default: the Skip Fuse app for iOS and Android. Darwin/ (Xcode) and Android/ (Gradle) are thin hosts.
//  - Browser: SwiftUIWeb's launcher sets SWIFTUIWEB_EMBEDDED=1 (TRIO_WEB=1 forces it for a native build check).
//    The same target then compiles against SwiftUIWeb with the WEB flag, and Web/ provides the BrowserApp entry point.
let environment = Context.environment
let isWeb = environment["SWIFTUIWEB_EMBEDDED"] == "1" || environment["TRIO_WEB"] == "1"

let package: Package = isWeb ? webPackage() : skipPackage()

func skipPackage() -> Package {
    Package(
        name: "Trio",
        defaultLocalization: "en",
        platforms: [.iOS(.v17), .macOS(.v14)],
        products: [
            .library(name: "Trio", type: .dynamic, targets: ["Trio"])
        ],
        dependencies: [
            .package(url: "https://github.com/skiptools/skip.git", from: "1.9.16"),
            .package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.0.0")
        ],
        targets: [
            .target(
                name: "Trio",
                dependencies: [.product(name: "SkipFuseUI", package: "skip-fuse-ui")],
                resources: [.process("Resources")],
                plugins: [.plugin(name: "skipstone", package: "skip")]
            )
        ]
    )
}

func webPackage() -> Package {
    Package(
        name: "Trio",
        platforms: [.macOS(.v15)],
        products: [.executable(name: "TrioWeb", targets: ["TrioWeb"])],
        // A real app depends on the published package instead:
        // .package(url: "https://github.com/Vitorsilveira31/SwiftUIWeb.git", from: "0.1.48")
        dependencies: [.package(path: "../..")],
        targets: [
            .target(
                name: "Trio",
                dependencies: [
                    .product(name: "SwiftUIWeb", package: "swiftuiweb"),
                    .product(name: "WebFoundation", package: "swiftuiweb")
                ],
                path: "Sources/Trio",
                // Skip-only files: the Skip config, the native app delegate and the catalogs (SwiftUIWeb's own tools
                // read catalogs; they are not built as resources).
                exclude: ["Skip", "Resources", "App/TrioAppDelegate.swift"],
                swiftSettings: [
                    .define("WEB"),
                    // The shared sources say `import SwiftUI` / `import Foundation`; in the browser those names are
                    // SwiftUIWeb and its Foundation-shaped companion. No source file needs to know.
                    .unsafeFlags(["-module-alias", "SwiftUI=SwiftUIWeb", "-module-alias", "Foundation=WebFoundation"]),
                    .swiftLanguageMode(.v6)
                ]
            ),
            .executableTarget(
                name: "TrioWeb",
                dependencies: [
                    "Trio",
                    .product(name: "SwiftUIWeb", package: "swiftuiweb"),
                    .product(name: "SwiftUIWebBrowser", package: "swiftuiweb")
                ],
                path: "Web",
                exclude: ["Resources"],
                swiftSettings: [.swiftLanguageMode(.v6)]
            )
        ]
    )
}
