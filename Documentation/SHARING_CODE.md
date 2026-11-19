# Sharing code with an Apple app

The views and models of an iOS, iPadOS or macOS app can build for the web unchanged. Each platform keeps only its entry
point: an `App` in Xcode, a `BrowserApp` for the web. This page shows how to lay that out.

## The layout

```text
MyApp/
├── Package.swift            the web package
├── Sources/Shared/          views, models, view models: plain SwiftUI, used by both targets
├── Web/MyWebApp.swift       @main struct MyWebApp: BrowserApp
└── iOS/                     the Xcode project; its target compiles Sources/Shared with Apple's SwiftUI
    ├── MyApp.xcodeproj
    └── MyApp.swift          @main struct MyApp: App
```

`MyApp/Sources/Shared/ContentView.swift` is ordinary SwiftUI:

```swift
import SwiftUI

public struct ContentView: View {
  @State private var count = 0
  public init() {}

  public var body: some View {
    Button("Tapped \(count) times") { count += 1 }
  }
}
```

## The web side

`Package.swift` builds the shared sources with `import SwiftUI` mapped to SwiftUIWeb, and a small executable that starts
them in the browser:

```swift
// swift-tools-version: 6.4
import PackageDescription

let alias: [SwiftSetting] = [.unsafeFlags(["-module-alias", "SwiftUI=SwiftUIWeb"])]

let package = Package(
  name: "MyApp",
  dependencies: [
    .package(url: "https://github.com/Vitorsilveira31/SwiftUIWeb.git", from: "0.1.10")
  ],
  targets: [
    .target(
      name: "Shared",
      dependencies: [.product(name: "SwiftUIWeb", package: "swiftuiweb")],
      swiftSettings: alias
    ),
    .executableTarget(
      name: "MyWebApp",
      dependencies: ["Shared", .product(name: "SwiftUIWebBrowser", package: "swiftuiweb")],
      path: "Web",
      swiftSettings: alias
    ),
  ]
)
```

`Web/MyWebApp.swift`:

```swift
import SwiftUI
import SwiftUIWebBrowser
import Shared

@main
struct MyWebApp: BrowserApp {
  var body: some Scene {
    WindowGroup { ContentView() }
  }
}
```

Then `./swiftweb dev` as in the [quickstart](QUICKSTART.md). The launcher sees the alias in `Package.swift` and lowers the
sources for it.

## The Apple side

Add the files of `MyApp/Sources/Shared` to the app target in Xcode (as references, so both sides edit the same files), and keep
the usual entry point:

```swift
import SwiftUI

@main
struct MyApp: App {
  var body: some Scene {
    WindowGroup { ContentView() }
  }
}
```

Xcode compiles the shared files against Apple's SwiftUI; nothing in them knows which one it gets.

## When the two must differ

Most apps need no conditions at all. When a screen should use an API that only one side has, branch on the module that
provides it:

```swift
#if canImport(SwiftUIWebWeb)
import SwiftUIWebWeb   // browser-only APIs: .documentHead, WebContentView, DOMViewRepresentable
#endif

Text("Settings")
#if canImport(SwiftUIWebWeb)
  .documentHead { HeadElement.meta(name: "description", content: "The app's settings") }
#endif
```

A package-defined flag (`.define("WEB")` in the web targets' `swiftSettings`) works too, and reads better when several
files branch.

What SwiftUIWeb does not have, such as UIKit, Combine, reflection and some Apple frameworks, is listed with what to use
instead in [limitations](LIMITATIONS.md). Code that must also build for the web avoids those or keeps them on the Apple
side.

## Examples

- [`Examples/UniversalApp`](../Examples/UniversalApp/README.md): one settings screen shared by an iOS/iPadOS Xcode
  project and the web package, with a `WEB` flag.
- [`Examples/FoodTruck`](../Examples/FoodTruck/README.md): Apple's Food Truck sample built for the web from Apple's own
  files, with the module aliases for SwiftUI, Charts, MapKit and Foundation, and stand-ins for frameworks the browser does
  not have.
