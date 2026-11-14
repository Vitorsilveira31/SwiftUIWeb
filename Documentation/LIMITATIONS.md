# What does not work, or works differently

SwiftUIWeb follows SwiftUI's names and behaviour, and a divergence from Apple's API is fixed in the framework rather than
documented away. Some things still cannot come across: they belong to frameworks that sit next to SwiftUI on Apple
platforms, they need a part of Swift that Embedded Swift leaves out, or the browser has nothing to back them with. This
page lists them, with what to use instead.

The per-capability contract (supported, fallback, no-op) is the [feature matrix](FEATURE_MATRIX.md); the changes that
need an edit in an application are in the [migration guide](MIGRATION.md).

## Combine

Combine is not part of SwiftUI, but most SwiftUI code meets it. A browser build has no Combine: the source lowerer stops
the build at every `import Combine` and every `Combine.X` reference in an application source (diagnostic
`combine-unsupported`), so the failure is reported at the line rather than at link time.

| You write | In SwiftUIWeb |
|---|---|
| `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject` | Work. The framework ships its own `ObservableObjectPublisher`; nothing else of Combine comes with it. |
| `@Observable` | Works, and is the recommended model. The lowerer turns each class into the form the Embedded runtime tracks. |
| `sink`, `assign`, `AnyCancellable`, `PassthroughSubject`, `CurrentValueSubject`, `Just`, operators | Not available. Use `@Observable` for state and `async`/`await`, `AsyncStream` and `Task` for streams of events. |
| `.onReceive(_:perform:)` | Not available (it takes a publisher). Use `.onChange(of:)`, `.task` or `.task(id:)`. |
| `Timer.publish(every:on:in:)` | Not available. Use `Timer.scheduledTimer(withTimeInterval:repeats:block:)`, `TimelineView` or a `.task` loop with `Task.sleep`. |
| `URLSession.dataTaskPublisher(for:)` | Not available. Use `try await URLSession.shared.data(for:)`. |

## Foundation

Apple's Foundation does not run in an Embedded browser build. The framework provides the parts applications use, with
Apple's names, and `WebFoundation` exports them together: `Data`, `Date`, `URL`, `UUID`, JSON coding, `UserDefaults`,
`NotificationCenter`, `Timer`, `NSPredicate`, streams, a `Regex` stand-in and more. Number and date formatting goes to
the browser's `Intl`, so the output follows the browser's locale data. What differs:

- **One thread.** The Swift side runs on one thread (a Web Worker by default). `DispatchQueue.global()` is the main queue
  and `Thread.detachNewThread` runs its block on the main actor: concurrency is cooperative, through Swift Concurrency,
  and does not run in parallel.
- **Numbers from `JSONSerialization`.** Integral JSON numbers come back as `Int` and the others as `Double`. Without
  Objective-C's `NSNumber` bridging, `json["count"] as? Double` is `nil` when the JSON says `3`; read either type.
- **No `[String: Any]`.** Embedded Swift cannot hold arbitrary `Any` values, so `userInfo` dictionaries (for example on
  networking errors) are not provided, and `NSKeyedArchiver` archives only `NSObject` subclasses that support it.
- **No Objective-C runtime.** Key-value coding and `value(forKey:)` answer `nil` where Apple's would raise an exception.
- **Regex literals** (`/.../`) are not available; `try Regex("...")` covers the common syntax. `NSPredicate` `MATCHES`
  does not support Unicode script properties such as `\p{Han}`.
- **Networking follows the browser.** `URLSession` goes through `fetch`, so CORS applies, a CORS rejection and a DNS
  failure both arrive as `.cannotConnectToHost`, and methods the browser refuses (such as `TRACE`) are `.unsupportedURL`.
- **Web content follows the page's policy.** Inline HTML in a `WebContentView` (`loadHTMLString(_:baseURL:)`) can only use a
  base URL on the app's own origin: the page's `base-uri 'self'` policy applies to it, so a base on another origin is
  ignored and relative URLs resolve against the app.

## Hosts other than the browser

The package builds and its tests run on macOS and Linux, with no Apple framework: the native build uses the same
`WebFoundation` the browser does, so a test exercises what ships. Those builds are for tests and tools, not for
applications, and they keep the browser's model where a host would otherwise differ:

- **Files** live in the same in-memory file system as in the browser; nothing reaches the disk.
- **Networking** has no transport until the host installs one; tests install a deterministic transport or a
  `URLProtocol` class.
- **Threads are real.** `DispatchQueue` is the host's libdispatch, and `Thread`, `NSLock` and `NSCondition` use pthreads,
  because the test runner runs tests in parallel.
- **The clock** is the operating system's.

The whole toolchain runs on Linux as well: the source lowerer, the Embedded WebAssembly build, bundling and the
Playwright suites (CI runs them on Chromium in `swift:6.4.0-noble`, Ubuntu 24.04, and runs the WebKit suites on
macOS). Three checks need Apple's SDK and stay on macOS: `make swiftui-parity`, which reads the
SDK's symbol graphs, `make layout-conformance`, which lays the same views out with SwiftUI, and
`make universal-app-ios-test`, which builds with Xcode. CI runs them with Xcode 27.2, the SDK the API baseline was recorded with.

## The Swift language under Embedded Swift

The browser build compiles with Embedded Swift, which leaves out the parts of the runtime that need full type metadata.

- **No reflection.** `Mirror`, `dump` and other code that inspects a value's structure at run time are not available.
- **Limited dynamic casts.** A cast that needs runtime type metadata (`as?` from an existential to an unrelated type, a
  check of a metatype) may not compile or link; keep types concrete or pass the concrete type you need.
- **`Codable` is generated.** Embedded Swift does not synthesize `Codable`; the source lowerer writes the conformances
  for the application's types before the build.
- **Platform conditions.** WASI matches no `os(...)` platform, so in application sources the lowerer treats
  `#if os(macOS)` as true: the macOS side of multiplatform code is the one that runs in the browser.

## Apple frameworks next to SwiftUI

Several Apple modules have a browser counterpart in SwiftUIWeb (Charts, MapKit, AVFoundation and AVKit, PhotosUI,
CoreLocation, UserNotifications, Security, UniformTypeIdentifiers, Transferable). These have none:

- **UIKit and AppKit.** There is no `UIViewRepresentable`, `NSViewRepresentable`, `UIHostingController`, `UIApplication`
  or `UIDevice`. To host a DOM element or a JavaScript widget, use `DOMViewRepresentable` or a `WebMountController`
  (`Sources/SwiftUIWebBrowser/WebMount.swift`). The value types SwiftUI modifiers take from UIKit, such as
  `UITextContentType` and `UIKeyboardType`, exist so those modifiers compile.
- **SwiftData.** It is not part of the framework. The lowerer rewrites `@Model` classes into observable ones and
  `@Query(sort:)` key paths into closures, for an in-memory stand-in that the application provides.
- **No browser equivalent:** WidgetKit, ActivityKit (Live Activities), App Intents, StoreKit, CloudKit, Metal, SpriteKit,
  SceneKit and RealityKit.

## Blend modes and filters

Drawing is composited by the browser, so some of Apple's operators have no CSS or canvas equivalent. The view modifiers
and the `GraphicsContext` API differ, and the table says which.

| You write | In SwiftUIWeb |
|---|---|
| `View.blendMode(.sourceAtop)`, `.destinationOver`, `.destinationOut` | Partial. An element cannot be composited against what is painted under it, so these render as `mix-blend-mode: normal`. The `data-blend-mode` attribute keeps the name. Use a `Canvas` with `GraphicsContext.BlendMode` to get the operator. |
| `View.blendMode(.plusDarker)` | Approximate. CSS has no plus-darker operator; the element renders as `normal`. |
| `GraphicsContext.BlendMode.clear` | Erases to transparency whatever the source alpha is. Fills and strokes in clear mode are drawn opaque with `destination-out`; text and images drawn in clear mode are not. |
| `GraphicsContext.BlendMode.plusDarker` | Approximate. The canvas has no plus-darker operator, so it draws as `darken`. |
| `GraphicsContext.Filter.colorMultiply(_:)` | Not available. A canvas filter takes only CSS filter functions; the color multiply needs SVG filter markup in the page. |
| `GraphicsContext.Filter.alphaThreshold(min:max:color:)` | Not available, for the same reason as `colorMultiply`. |
| `GraphicsContext.Filter.colorMatrix(_:)`, `luminanceToAlpha`, `alphaMultiply(_:)` | Not available. No CSS filter function expresses them. |
| `GraphicsContext.Filter.colorShader`, `distortionShader`, `layerShader` | Not available. These need a Metal shader, which the browser does not run. |
| `ShadowOptions.shadowOnly`, `shadowAbove`, `invertsAlpha`, `disablesGroup` | Accepted, with no effect. A CSS drop shadow draws beside its object. |
| `Filter.shadow(blendMode:)` with a blend other than `.normal` | Accepted, with no effect. The drop shadow composites normally. |
| `BlurOptions` (`opaque`, `dithersResult`) and `FilterOptions.linearColor` | Accepted, with no effect. The canvas blurs and filters in sRGB with a plain Gaussian. |

## Modifiers that cannot do anything in a browser

Some modifiers compile and have no effect, because the browser has nothing for them to drive. The feature matrix lists
each one as `no-op`; the main one is `sensoryFeedback` (no haptics on the web). Others use a browser substitute and are
marked `fallback` there: maps use MapLibre, date pickers use the browser's inputs, local notifications use the
Notifications API, and `PasteButton` uses the clipboard API.
