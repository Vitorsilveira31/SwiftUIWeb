// swift-tools-version: 6.1
import PackageDescription

// One package, one shared source tree (Sources/ClipPlayer), two hosts:
//  - Default: a SwiftUI library for iOS. Darwin/ (Xcode) is the thin app that loads it.
//  - Browser: SwiftUIWeb's launcher sets SWIFTUIWEB_EMBEDDED=1. The same target then compiles against SwiftUIWeb
//    with the WEB flag, and Web/ provides the BrowserApp entry point.
let isWeb = Context.environment["SWIFTUIWEB_EMBEDDED"] == "1"

let package: Package = isWeb ? webPackage() : applePackage()

func applePackage() -> Package {
    Package(
        name: "ClipPlayer",
        platforms: [.iOS(.v17), .macOS(.v14)],
        products: [.library(name: "ClipPlayer", targets: ["ClipPlayer"])],
        targets: [.target(name: "ClipPlayer")]
    )
}

func webPackage() -> Package {
    Package(
        name: "ClipPlayer",
        platforms: [.macOS(.v15)],
        products: [.executable(name: "ClipPlayerWeb", targets: ["ClipPlayerWeb"])],
        // A real app depends on the published package instead of a path.
        dependencies: [.package(path: "../..")],
        targets: [
            .target(
                name: "ClipPlayer",
                dependencies: [
                    .product(name: "SwiftUIWeb", package: "swiftuiweb"),
                    .product(name: "WebFoundation", package: "swiftuiweb"),
                    .product(name: "SwiftUIWebAVKit", package: "swiftuiweb"),
                    .product(name: "SwiftUIWebAVFoundation", package: "swiftuiweb")
                ],
                path: "Sources/ClipPlayer",
                swiftSettings: [
                    .define("WEB"),
                    // The shared sources import Apple's module names; in the browser those names are SwiftUIWeb's
                    // modules. No source file needs to know.
                    .unsafeFlags([
                        "-module-alias", "SwiftUI=SwiftUIWeb",
                        "-module-alias", "Foundation=WebFoundation",
                        "-module-alias", "AVKit=SwiftUIWebAVKit",
                        "-module-alias", "AVFoundation=SwiftUIWebAVFoundation"
                    ]),
                    .swiftLanguageMode(.v6)
                ]
            ),
            .executableTarget(
                name: "ClipPlayerWeb",
                dependencies: [
                    "ClipPlayer",
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
