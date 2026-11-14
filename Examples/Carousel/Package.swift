// swift-tools-version: 6.1
import PackageDescription

// One package, one shared source tree (Sources/Carousel), two hosts:
//  - Default: a SwiftUI library for iOS. Darwin/ (Xcode) is the thin app that loads it.
//  - Browser: SwiftUIWeb's launcher sets SWIFTUIWEB_EMBEDDED=1. The same target then compiles against SwiftUIWeb
//    with the WEB flag, and Web/ provides the BrowserApp entry point.
let isWeb = Context.environment["SWIFTUIWEB_EMBEDDED"] == "1"

let package: Package = isWeb ? webPackage() : applePackage()

func applePackage() -> Package {
    Package(
        name: "Carousel",
        platforms: [.iOS(.v17), .macOS(.v14)],
        products: [.library(name: "Carousel", targets: ["Carousel"])],
        targets: [.target(name: "Carousel")]
    )
}

func webPackage() -> Package {
    Package(
        name: "Carousel",
        platforms: [.macOS(.v15)],
        products: [.executable(name: "CarouselWeb", targets: ["CarouselWeb"])],
        // A real app depends on the published package instead of a path.
        dependencies: [.package(path: "../..")],
        targets: [
            .target(
                name: "Carousel",
                dependencies: [
                    .product(name: "SwiftUIWeb", package: "swiftuiweb"),
                    .product(name: "WebFoundation", package: "swiftuiweb")
                ],
                path: "Sources/Carousel",
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
                name: "CarouselWeb",
                dependencies: [
                    "Carousel",
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
