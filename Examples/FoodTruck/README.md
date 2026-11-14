# Food Truck: Apple's sample, in the browser

[Apple's Food Truck](https://github.com/apple/sample-food-truck) (a SwiftUI multiplatform app: sidebar navigation,
tables, charts, a map, StoreKit subscriptions, passkey accounts, WeatherKit, App Intents) compiled for the browser by
SwiftUIWeb with a small set of source adaptations, listed below. The goal of this example is to find what SwiftUI the
framework lacks, so the gaps it exposed were closed in the framework rather than worked around in the sample.

```text
FoodTruck/
├── Sources/
│   ├── FoodTruck/         Apple's App/ folder, with the adaptations listed below (App.swift is excluded: it is the @main of the Xcode target)
│   ├── FoodTruckKit/      Apple's FoodTruckKit/Sources, with the adaptations listed below
│   ├── Shims/             stand-ins for Apple frameworks with no browser counterpart (StoreKit, WeatherKit, ...)
│   ├── FoodTruck/WebAdapters/, FoodTruckKit/WebAdapters/   the few files that replace Apple code bound to a platform
│   └── README-apple.md    Apple's own README for the sample
├── Web/                   the BrowserApp entry point (what App.swift is on Apple platforms)
├── Package.swift          the web package: module aliases, exclusions
└── LICENSE.txt            Apple's sample-code license, which covers Sources/FoodTruck and Sources/FoodTruckKit
```

## Run it

From the SwiftUIWeb root:

```sh
swift Tools/swiftuiweb-run.swift --path Examples/FoodTruck --product FoodTruckWeb --port 8100
```

## How the source is kept close to Apple's

Apart from the adaptations listed in the next section, the files under `Sources/FoodTruck` and `Sources/FoodTruckKit`
are Apple's own code.

- `Package.swift` aliases the Apple module names to SwiftUIWeb's (`-module-alias SwiftUI=SwiftUIWeb`,
  `Charts=SwiftUIWebCharts`, `MapKit=SwiftUIWebMapKit`, `Foundation=WebFoundation`, ...), so `import SwiftUI` and
  friends in Apple's files resolve to the framework.
- Apple frameworks with no browser counterpart resolve to the modules in `Sources/Shims`. They keep Apple's API
  and give it a browser meaning: StoreKit is a demonstration store (same three products as `Products.storekit`,
  purchases persisted in local storage), WeatherKit answers with a deterministic forecast, `AuthenticationServices`
  provides the environment value the account screens read.
- A browser is a desktop host: the source lowering evaluates `os(macOS)` conditions in application sources as true, so
  Apple's macOS branches (HSplitView, the Orders table, the Social Feed banner, the store sheet) run instead of
  compiling to nothing (WASI matches no platform).
- The Swift-to-Embedded constraints (no key paths, no dynamic casts, no existentials) are handled by the source
  lowering that SwiftUIWeb runs on every app: `KeyPathComparator(\Order.status)` and `TableColumn(value: \.status)`
  become closures, `error.localizedDescription` becomes a call to a free function, a class with a generic method is
  marked `final`.

## Adaptations to Apple's code, and why

SwiftUIWeb browser builds reject `import Combine` (the preflight in the lowering tool requires Swift Observation and
async/await instead). So the observable state Apple built on Combine was moved to `@Observable`, and the views that
observed it read it as plain properties, `@Environment`, or `@State`:

- `FoodTruckKit/Store/StoreProductController.swift`, `FoodTruckKit/Store/StoreSubscriptionController.swift`:
  `ObservableObject` and `@Published` become `@Observable`; the store views (`UnlockFeatureView`, `SubscriptionStoreView`,
  `SocialFeedPlusSettings`, `SocialFeedView`, `SalesHistoryView`) observe them as plain properties.
- `FoodTruckKit/Model/FoodTruckModel.swift`: removed an unused `import Combine`.
- `FoodTruck/Navigation/ContentView.swift`, `FoodTruck/Account/AccountView.swift`, `FoodTruck/Account/SignUpView.swift`:
  the account store is passed with `.environment(_:)` and read with `@Environment(AccountStore.self)`.
- `Shims/WebStoreKit/StoreKit.swift`: `@MainActor` is applied to `RequestReviewAction.callAsFunction()` rather than the
  whole struct, because its `EnvironmentKey` default is built from a nonisolated context.
- `FoodTruck/Store/RefundView.swift`: `@State private var selectedTransactionID: UInt64? = nil` has an explicit `nil`
  (the value Swift already uses). Without it the Embedded build crashes; see Known issues below.

The Apple `Account/AccountStore.swift` (passkeys through AuthenticationServices) is deleted from this package. The web
adapter below replaces it.

| File | Replaces | Reason |
| --- | --- | --- |
| `FoodTruckKit/WebAdapters/WebAccountStore.swift` | `Account/AccountStore.swift` (deleted) | Passkeys against `example.com` cannot run in a browser; sign-in is local and persisted. |
| `FoodTruck/WebAdapters/WebDetailedMapView.swift` | `City/DetailedMapView.swift` | It wraps `MKMapView` in a UIKit/AppKit view controller; this is the same view drawn with the framework's `Map`. |
| `FoodTruck/WebAdapters/WebAppRoot.swift` | `App.swift` | The `@main` of the Xcode target; this holds the same model and store for the browser entry point. |
| `FoodTruckKit/WebAdapters/Subscription+DynamicMembers.swift` | nothing (adds members) | `Subscription` forwards `Product` members through `@dynamicMemberLookup` key paths, which Embedded Swift lacks. |
| `ShowTopDonutsIntent*.swift` (excluded) | App Intents (Siri, Shortcuts) | A browser has neither. |

## Known issues

### Embedded swift-frontend crash on an uninitialized optional `@State`

Swift 6.4 (`swift-6.4-RELEASE`) crashes while compiling the `FoodTruck` module for the browser when an optional `@State`
has no initializer:

```swift
struct RefundView: View {
    @State private var selectedTransactionID: UInt64?   // crashes the Embedded build
    // ...
}
```

The crash is `While emitting lazy specialized class metadata for type 'StateBox<Optional<UInt64>>'`. Writing
`@State private var selectedTransactionID: UInt64? = nil` avoids it, and the default value is the same. The same
declaration does not reproduce in `Tests/Apps/EmbeddedLoweringConformanceApp` (a small `List(selection:)` probe with
`.disabled` and `.task` builds), so the trigger needs more of the `FoodTruck` module. Not yet characterized: whether
`Int?`, `UInt32?`, `Int64?` or `UInt?` crash the same way.

## Status

Every panel runs and is interactive: the animated Truck landing page (the `Canvas` header, the Orders tiling, the donut
lattice, the forecast chart, the flowing tags), Orders (a sortable `Table`), Social Feed and its store sheet, Sales
History and Top 5 (charts with annotations and image axis labels), the donut gallery and editor, the cities with a
real map, local sign-in and the demonstration store. It takes the framework features Apple's code relies on:

- user-defined `Layout`s are offered the proposal their parent gave them, place their subviews for it, and size by
  what the browser measured (`HeroSquareTilingLayout`, `DonutLatticeLayout`, `FlowLayout`, ...);
- `Canvas` / `GraphicsContext` is painted on a 2D context (gradients, layers, transforms, images);
- `NavigationSplitView` columns, table cells and `Grid`s inside native widgets are laid out by the browser with CSS;
- `GeometryReader` / `TimelineView` re-render only their own subtree (an animated header does not re-render the page).

Known gaps: the city map needs WebGL (headless Chrome without it shows MapLibre's notice); the Orders table scrolls
sideways on a phone instead of reflowing. A compact viewport (<= 700px) is a push navigation (sidebar, then detail with a
Back button), sheets are centered form sheets, and the system colors are Apple's palette. See the SwiftUIWeb commit
history for the framework APIs this added (Table selection and sorting, Charts axes and marks, `AttributedString`,
`List(selection:)`, asset-catalog namespaces and custom symbols, `Color(nsColor:)`, `navigationSplitViewColumnWidth`,
and the Foundation names an app expects).
