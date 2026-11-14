// swift-tools-version: 6.1
import PackageDescription

// One package, one shared source tree (Sources/PhotoEditor), two hosts:
//  - Default: a SwiftUI library for iOS. Darwin/ (Xcode) is the thin app that loads it.
//  - Browser: SwiftUIWeb's launcher sets SWIFTUIWEB_EMBEDDED=1. The same target then compiles against SwiftUIWeb
//    with the WEB flag, and Web/ provides the BrowserApp entry point.
let isWeb = Context.environment["SWIFTUIWEB_EMBEDDED"] == "1"

let package: Package = isWeb ? webPackage() : applePackage()

func applePackage() -> Package {
    Package(
        name: "PhotoEditor",
        platforms: [.iOS(.v17), .macOS(.v14)],
        products: [.library(name: "PhotoEditor", targets: ["PhotoEditor"])],
        targets: [.target(name: "PhotoEditor")]
    )
}

func webPackage() -> Package {
    Package(
        name: "PhotoEditor",
        platforms: [.macOS(.v15)],
        products: [.executable(name: "PhotoEditorWeb", targets: ["PhotoEditorWeb"])],
        // A real app depends on the published package instead of a path.
        dependencies: [.package(path: "../..")],
        targets: [
            .target(
                name: "PhotoEditor",
                dependencies: [
                    .product(name: "SwiftUIWeb", package: "swiftuiweb"),
                    .product(name: "WebFoundation", package: "swiftuiweb"),
                    .product(name: "SwiftUIWebPhotosUI", package: "swiftuiweb")
                ],
                path: "Sources/PhotoEditor",
                swiftSettings: [
                    .define("WEB"),
                    // The shared sources import Apple's module names; in the browser those names are SwiftUIWeb's
                    // modules. No source file needs to know.
                    .unsafeFlags([
                        "-module-alias", "SwiftUI=SwiftUIWeb",
                        "-module-alias", "Foundation=WebFoundation",
                        "-module-alias", "PhotosUI=SwiftUIWebPhotosUI"
                    ]),
                    .swiftLanguageMode(.v6)
                ]
            ),
            .executableTarget(
                name: "PhotoEditorWeb",
                dependencies: [
                    "PhotoEditor",
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
