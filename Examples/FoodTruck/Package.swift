// swift-tools-version: 6.4
import PackageDescription

// Apple's Food Truck sample (Sources/FoodTruck and Sources/FoodTruckKit, unmodified) running in the browser. The web package compiles its sources as they
// are: `import SwiftUI`, `import Charts`, `import MapKit` ... are aliased to SwiftUIWeb's modules, and the Apple
// frameworks that have no browser counterpart resolve to the stand-ins in Shims/. Only the entry point differs: Web/
// replaces App.swift, as every SwiftUIWeb example does.
let aliases = [
  "SwiftUI=SwiftUIWeb",
  "Charts=SwiftUIWebCharts",
  "MapKit=SwiftUIWebMapKit",
  "CoreLocation=SwiftUIWebCoreLocation",
  "UniformTypeIdentifiers=SwiftUIWebUniformTypeIdentifiers",
  "os=WebOS",
  "StoreKit=WebStoreKit",
  "WeatherKit=WebWeatherKit",
  "AuthenticationServices=WebAuthenticationServices",
  "AppIntents=WebAppIntents",
  "UIKit=WebUIKit"
] + (Context.environment["SWIFTUIWEB_EMBEDDED"] == "1" ? ["Foundation=WebFoundation"] : [])

let aliasFlags = aliases.flatMap { ["-module-alias", $0] }
let webSettings: [SwiftSetting] = [
  .define("WEB"),
  .unsafeFlags(aliasFlags),
  .swiftLanguageMode(.v5)
]
let swiftUIWeb: [Target.Dependency] = [
  .product(name: "SwiftUIWeb", package: "swiftuiweb"),
  .product(name: "SwiftUIWebCharts", package: "swiftuiweb"),
  .product(name: "SwiftUIWebMapKit", package: "swiftuiweb"),
  .product(name: "SwiftUIWebCoreLocation", package: "swiftuiweb"),
  .product(name: "SwiftUIWebUniformTypeIdentifiers", package: "swiftuiweb"),
  .product(name: "WebFoundation", package: "swiftuiweb")
]
let shimNames = ["OS", "StoreKit", "WeatherKit", "AuthenticationServices", "AppIntents", "UIKit"]
let shims = shimNames.map { name in
  Target.target(name: "Web\(name)", dependencies: [.product(name: "SwiftUIWeb", package: "swiftuiweb"), .product(name: "SwiftUIWebCoreLocation", package: "swiftuiweb")],
                path: "Sources/Shims/Web\(name)", swiftSettings: [.swiftLanguageMode(.v5)])
}
let shimDependencies: [Target.Dependency] = shimNames.map { .target(name: "Web\($0)") }

let package = Package(
  name: "FoodTruckWeb",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "FoodTruckWeb", targets: ["FoodTruckWeb"])],
  dependencies: [.package(path: "../..")],
  targets: shims + [
    .target(
      name: "FoodTruckKit",
      dependencies: swiftUIWeb + shimDependencies,
      path: "Sources/FoodTruckKit",
      exclude: ["Assets.xcassets", "Resources"],
      swiftSettings: webSettings
    ),
    .target(
      name: "FoodTruck",
      dependencies: ["FoodTruckKit"] + swiftUIWeb + shimDependencies,
      path: "Sources/FoodTruck",
      exclude: [
        "App.swift", "Assets.xcassets", "Preview Content", "ar.lproj", "en.lproj",
        "Entitlements-All.entitlements", "Entitlements.entitlements", "Food-Truck-All-Info.plist", "Food-Truck-Info.plist",
        "Store/Products.storekit",
        // App Intents (Siri, Shortcuts) and the native map controller have no browser counterpart; WebAdapters/ replaces the map.
        "Donut/ShowTopDonutsIntent.swift", "Donut/ShowTopDonutsIntentView.swift", "City/DetailedMapView.swift"
      ],
      swiftSettings: webSettings
    ),
    .executableTarget(
      name: "FoodTruckWeb",
      dependencies: ["FoodTruck", "FoodTruckKit", .product(name: "SwiftUIWeb", package: "swiftuiweb"),
                     .product(name: "SwiftUIWebBrowser", package: "swiftuiweb")],
      path: "Web",
      exclude: ["Resources"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    )
  ]
)
