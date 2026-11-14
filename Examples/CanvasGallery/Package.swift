// swift-tools-version: 6.1
import PackageDescription

// One package, one shared source tree (Sources/CanvasGallery), two hosts:
//  - Default: a SwiftUI library for iOS. Darwin/ (Xcode) is the thin app that loads it.
//  - Browser: SwiftUIWeb's launcher sets SWIFTUIWEB_EMBEDDED=1. The same target then compiles against SwiftUIWeb
//    with the WEB flag, and Web/ provides the BrowserApp entry point.
let isWeb = Context.environment["SWIFTUIWEB_EMBEDDED"] == "1"

let package: Package = isWeb ? webPackage() : applePackage()

func applePackage() -> Package {
    Package(
        name: "CanvasGallery",
        platforms: [.iOS(.v17), .macOS(.v14)],
        products: [.library(name: "CanvasGallery", targets: ["CanvasGallery"])],
        targets: [.target(name: "CanvasGallery")]
    )
}

func webPackage() -> Package {
    Package(
        name: "CanvasGallery",
        platforms: [.macOS(.v15)],
        products: [.executable(name: "CanvasGalleryWeb", targets: ["CanvasGalleryWeb"])],
        // A real app depends on the published package instead of a path.
        dependencies: [.package(path: "../..")],
        targets: [
            .target(
                name: "CanvasGallery",
                dependencies: [
                    .product(name: "SwiftUIWeb", package: "swiftuiweb"),
                    .product(name: "WebFoundation", package: "swiftuiweb")
                ],
                path: "Sources/CanvasGallery",
                swiftSettings: [
                    .define("WEB"),
                    // The shared sources import Apple's module names; in the browser those names are SwiftUIWeb's
                    // modules. No source file needs to know.
                    .unsafeFlags([
                        "-module-alias", "SwiftUI=SwiftUIWeb",
                        "-module-alias", "Foundation=WebFoundation"
                    ]),
                    .swiftLanguageMode(.v6)
                ]
            ),
            .executableTarget(
                name: "CanvasGalleryWeb",
                dependencies: [
                    "CanvasGallery",
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
