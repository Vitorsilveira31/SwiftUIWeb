# Quickstart

From an empty folder to a SwiftUI app running in your browser, then to a folder of static files you can host anywhere.

## Requirements

| Tool | Why | Install |
|---|---|---|
| Swift 6.4 from swift.org | Compiles the app. Xcode's own compiler cannot build WebAssembly, so use the swift.org toolchain (Xcode can stay installed next to it). | [swift.org/install](https://www.swift.org/install/), or `swiftly install 6.4.0` |
| Swift SDK for WebAssembly, 6.4.0 | The target the app is compiled for. It must be the SDK of the exact same Swift release; it contains the Embedded SDK SwiftUIWeb uses. | see below |
| [Bun](https://bun.sh) | Runs the build scripts and the development server. | `curl -fsSL https://bun.sh/install \| bash` or `brew install oven-sh/bun/bun` |
| Binaryen (optional) | Shrinks release builds by about a third. | `brew install binaryen` or `apt-get install binaryen` |

macOS 14 or later, or Linux (the CI uses the `swift:6.4.0-noble` image). Install the WebAssembly SDK with the Swift 6.4
toolchain on your `PATH`:

```sh
swift sdk install \
  https://download.swift.org/swift-6.4.0-release/wasm-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d
```

You do not have to get everything right first: `./swiftweb doctor` (step 2) lists everything missing at once, each with
the command that installs it, and every build runs the same check.

## 1. Create the app

A SwiftUIWeb app is an ordinary Swift package with an executable target:

```text
MyApp/
├── Package.swift
├── Sources/MyApp/MyApp.swift
└── Resources/          (optional) head.html, app.css, images and fonts for the browser
```

`MyApp/Package.swift`:

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "MyApp",
  dependencies: [
    .package(url: "https://github.com/Vitorsilveira31/SwiftUIWeb.git", from: "0.1.28")
  ],
  targets: [
    .executableTarget(
      name: "MyApp",
      dependencies: [
        .product(name: "SwiftUIWeb", package: "swiftuiweb"),
        .product(name: "SwiftUIWebBrowser", package: "swiftuiweb"),
      ],
      // `import SwiftUI` compiles against SwiftUIWeb, so the views read exactly as on iOS.
      swiftSettings: [.unsafeFlags(["-module-alias", "SwiftUI=SwiftUIWeb"])]
    )
  ]
)
```

`MyApp/Sources/MyApp/MyApp.swift`:

```swift
import SwiftUI
import SwiftUIWebBrowser

@main
struct MyApp: BrowserApp {
  var body: some Scene {
    WindowGroup { ContentView() }
  }
}

struct ContentView: View {
  @State private var name = ""

  var body: some View {
    NavigationStack {
      Form {
        TextField("Your name", text: $name)
        Text(name.isEmpty ? "Hello!" : "Hello, \(name)!")
      }
      .navigationTitle("MyApp")
    }
  }
}
```

Two things differ from an app in Xcode, and only in the entry point: the app conforms to `BrowserApp`, which comes from
`SwiftUIWebBrowser`. Everything below `WindowGroup` is ordinary SwiftUI.

**About the module alias.** `-module-alias SwiftUI=SwiftUIWeb` lets `import SwiftUI` mean SwiftUIWeb in this package,
so code moves between your Apple app and the web unchanged. SwiftPM accepts `unsafeFlags` in the package you build (it
refuses them only in packages used as dependencies), which is the case for an app. If you prefer no flag, leave the
`swiftSettings` line out and write `import SwiftUIWeb` instead of `import SwiftUI`. To build the same sources for iOS
too, see [sharing code with an Apple app](SHARING_CODE.md).

## 2. Run it

Once, in the package folder:

```sh
swift package --allow-writing-to-package-directory web init
```

It writes `./swiftweb`, a short script that runs SwiftUIWeb's tools for your package from the copy SwiftPM resolved
(commit it with your code). Then:

```sh
./swiftweb dev      # debug build, served; saving a file rebuilds and reloads the page
./swiftweb build    # optimized release bundle in .build/browser/MyApp
./swiftweb run      # the release bundle, served
./swiftweb doctor   # what the toolchain is missing, with the command that installs each piece
```

`dev` and `run` print the address (the first free port from 8080). `--port 8080` picks one; with several executable
targets, name the one to run: `./swiftweb dev MyApp`. The first build compiles the source lowerer once, which takes a
couple of minutes; later builds take seconds to a minute. Keep `.build/` out of version control.

Why a script and not an IDE run button: Xcode cannot build the WebAssembly target, so the build runs in a terminal next
to your editor. Any editor works, since the loop reacts to files being saved. More in
[the development workflow](DEVELOPMENT_WORKFLOW.md#hot-reload-save-a-file-the-page-updates).

## 3. Build the app

Most SwiftUI code compiles unchanged: views, layout, state and `@Observable`, navigation, lists, forms, sheets, charts,
maps, media and the rest listed in the [feature matrix](FEATURE_MATRIX.md). What does not come across (Combine, UIKit,
reflection, some Apple frameworks) is listed with what to write instead in [limitations](LIMITATIONS.md). Using an API
that is not available fails the build at the line, with an explanation (for example `combine-unsupported` for
`import Combine`).

**Navigation and addresses.** `NavigationStack`, `NavigationSplitView` and `TabView` keep the browser's address and
history in step: Back and Forward work, and a reload or a shared link opens the same screen. Read the address in
`onOpenURL`:

```swift
NavigationStack(path: $path) { content }
  .onOpenURL { url in path = route(url) }
```

[The browser shell guide](BROWSER_APP_SHELL.md) covers addresses per screen, the page title, the theme and styling.

**Networking.** `URLSession` works as on Apple platforms (`try await URLSession.shared.data(from: url)`), through the
browser's `fetch`, so CORS applies. For signed-in requests, prefer a cookie the server sets (`HttpOnly; Secure;
SameSite`): the default credentials policy sends it to your own origin without a token ever living in app storage.

**Browser-only APIs** that SwiftUI has no equivalent for live in `SwiftUIWebWeb` (add the product, then `import
SwiftUIWebWeb`): `.documentHead` for the page's `<meta>` tags, `WebContentView` for web content,
`DOMViewRepresentable` to host any DOM element or JavaScript widget. In code you also build for iOS, put those calls
under `#if canImport(SwiftUIWebWeb)`.

**Static files.** Files in `Resources/` (or `Web/Resources/`) are copied next to `index.html`. Two have a special role:
`head.html` is inserted into the page's `<head>` (web fonts, `<meta>` tags), and `app.css` is loaded after the
framework's stylesheet (colors, fonts, spacing through its tokens). See [the browser shell guide](BROWSER_APP_SHELL.md).

## 4. Test it

Put logic and view models in a library target and test them with `swift test`: SwiftUIWeb builds natively on macOS and
Linux, so tests run without a browser. To test the running app, build it (`./swiftweb build`), serve the bundle and drive
it with a browser automation tool such as [Playwright](https://playwright.dev); the framework's own browser suites in
`Tools/test-*.mjs` are examples.

## 5. Ship it

`./swiftweb build` writes a folder of static files. [Deploying](DEPLOYMENT.md) explains what to upload and how to set up
the host (routes, caching, compression, headers).

## When something fails

| Symptom | What to do |
|---|---|
| `./swiftweb` says SwiftUIWeb is not resolved | Run `swift package resolve` once, then try again. |
| The build stops before compiling and lists missing tools | Install what it lists (or run `./swiftweb doctor`), then build again. |
| `no Swift compiler with a WebAssembly SDK found` | The WebAssembly SDK must match the toolchain: check `swift --version` and `swift sdk list`, and install the SDK of that exact release (above). |
| An error at an `import`, such as `combine-unsupported` | The API has no browser counterpart; [limitations](LIMITATIONS.md) says what to use instead. |
| The page is blank and the console reports a Content-Security-Policy violation | A script, style or font comes from somewhere the page's policy does not allow; see the policy in [the browser shell guide](BROWSER_APP_SHELL.md). |
| The app works locally but not when hosted | Serve it from the root of the domain and answer every route with `index.html`; see [deploying](DEPLOYMENT.md). |

Something else: open an issue with the bug template, or ask in Discussions.
