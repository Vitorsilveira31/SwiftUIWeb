# SwiftUIWeb architecture

SwiftUIWeb has one supported Web architecture:

```text
SwiftUI-compatible API
        ↓
Fiber / ViewGraph identity and reconciliation
        ↓
CSS layout (flexbox and grid) styled from the semantic layout
        ↓
BrowserIO ABI and semantic coordinators
        ↓
Embedded Swift WASM
        ↓
native browser DOM, measurement, input, scrolling and accessibility
```

## Responsibilities

- **Swift** describes view semantics, bindings, state, environment and user
  intent. Application code remains ordinary SwiftUI-shaped source.
- **Fiber / ViewGraph** owns stable semantic identity, reconciliation,
  lifecycle and retained state. Identity is never derived from DOM order.
- **CSS layout** (`Tools/css-layout.js`) turns the
  layout intent Swift describes (`data-layout-kind` and its attributes) into
  flexbox and grid declarations that give SwiftUI's proposal/response sizes
  ([`Architecture/CSS_LAYOUT.md`](Architecture/CSS_LAYOUT.md)). The browser
  does the measuring and the placing.
- **BrowserIO** is the only Swift-to-browser bridge. It coordinates events,
  DOM commits, focus, scrolling, presentations, intrinsic measurement and
  browser capabilities.
- **Embedded Swift WASM** is the only supported browser Swift runtime. Native
  Swift builds remain useful for API and semantic unit tests, but are not a
  second Web runtime.
- **Swift and JavaScript are the only runtime languages.** The Fiber runtime is plain Swift: the structural
  arena, child matching (`ChildPlan`), the dependency graph, the lazy-list math (`_LazyLayoutEngine`), the mutation
  and word buffers, ISO 8601 and JSON. The JavaScript host answers what the browser answers best: NSPredicate
  evaluation, number formatting and string folding. There is no native runtime library and no C ABI between them
  beyond BrowserIO's own bridge. The development tools under `Tools/` are Swift (the source lowerer) and JavaScript.
- **The browser** owns platform-dependent text shaping, fonts, native input,
  physical scrolling and the final DOM/accessibility primitives.

## Modules

Each target under `Sources/` has one job (the full description, with the dependency arrows, is in
[`Sources/README.md`](../Sources/README.md)).

| Target | What it does |
|---|---|
| `SwiftUIWeb` | The module apps import. It re-exports the API modules on every host. |
| `SwiftUIWebCore` | The SwiftUI-shaped API: views, modifiers, state, environment and the layout intent. It is renderer-neutral. |
| `SwiftUIWebFeatures` | API that Core does not use, such as `@AppStorage`, `AttributedString`, file documents and split views. |
| `SwiftUIWebFiber` | The runtime that keeps the view tree alive: identity, invalidation, reconciliation and lazy lists. |
| `SwiftUIWebHTML` | Encodes the rendered tree as the binary publication the page applies, and writes plain HTML for static rendering and tests. |
| `SwiftUIWebBrowser` | The browser host: `BrowserApp`, mounting in the page, CSS layout emission, history and drag and drop. |
| `SwiftUIWebBrowserIO` | The one Swift-to-JavaScript bridge: events, DOM commits, timers, storage and cookies. |
| `CSwiftUIWebBrowserIO` | The C entry points WebAssembly calls into, which connect concurrency to the browser event loop. |
| `SwiftUIWebNetworking` | `URLSession`, `URLRequest`, cookies and `URLError`; the browser uses `fetch`. |
| `SwiftUIWebInternationalization` | Dates, numbers and `DatePicker`, without Foundation. |
| `SwiftUIWebLocking` | The libc adapter for the few process-wide locks the runtime needs. |
| `SwiftUIWebTransferable` | `Transferable` and the Codable replacement Embedded Swift needs. |
| `SwiftUIWebUniformTypeIdentifiers` | A small `UTType`. |
| `WebFoundation` | Foundation names that Embedded Swift lacks: JSON, `NSPredicate`, measurements and locale. |
| `WebOSLog` | `Logger`, written to the browser console. |
| `SwiftUIWebCrypto` | SHA-2, HMAC, AES, P-256 and Curve25519 with the CryptoKit API. |
| `SwiftUIWebSecurity` | `SecItem` keychain calls, backed by encrypted IndexedDB, and web sessions. |
| `SwiftUIWebCoreLocation` | Location services through the browser. |
| `SwiftUIWebUserNotifications` | Permission and local notifications. |
| `SwiftUIWebCharts` | `Chart`, marks and axes. |
| `SwiftUIWebMapKit` | `Map`, drawn by MapLibre. |
| `SwiftUIWebAVFoundation` | `AVPlayer`-shaped playback that controls a native media element. |
| `SwiftUIWebAVKit` | `VideoPlayer` with ready-made controls, on top of AVFoundation. |
| `SwiftUIWebMotion` | `MotionView` and `LottieContainer` with SkipMotion's API, drawn by lottie-web. |
| `SwiftUIWebPhotosUI` | `PhotosPicker`, reading files from the browser. |
| `SwiftUIWebWeb` | `WebContentView`, `DOMViewRepresentable`, the document head and credentials. |
| `SwiftUIWebEmbeddedCoreProbe` | Not shipped. A target the size tools build to measure the minimum WebAssembly artifact. |

## How a change reaches the screen

A state write goes to `StateStore` (`Sources/SwiftUIWebCore/State.swift`), which records the source that changed and
invalidates the owners that read it. Fiber (`Sources/SwiftUIWebFiber`) reconciles only the subtrees those owners select,
or the root when a source has no single owner, and updates the leaf bindings that a value feeds directly. `BinaryFiberEncoder`
(`Sources/SwiftUIWebHTML/BinaryEncoder.swift`) writes the changed part of the tree as a binary publication. In the
worker runtime the Worker posts it to the page (`Tools/embedded-worker.js`, received by `Tools/embedded-worker-client.js`).
The page applies it to the DOM in `Tools/embedded-dom.js`, and the browser lays the result out with CSS. Input events
travel the other way: the page calls the `dispatch_named` export (`embedded_browser_dispatch_named`), Swift runs the
handler, and the cycle starts again. The record formats are in [`Architecture/BINARY_PATCHES.md`](Architecture/BINARY_PATCHES.md).

## Build and validation boundary

Web execution always goes through `Tools/run-browser.sh`, which dispatches to
the Embedded builder and produces a browser bundle containing `app.wasm`.
There is no Standard/WASI browser product, JavaScriptKit runtime, PackageToJS
path or runtime-selection environment variable. The boundary is enforced by:

```sh
make single-browser-runtime-audit
```

The Embedded build may use WASI SDK components internally; that does not add a
second runtime architecture.

## Source lowering

Embedded Swift source lowering is a build-time compatibility pass. It rewrites
only disposable compiler input for constructs that the current Embedded
toolchain cannot compile directly (for example selected SwiftUI-shaped
KeyPath spellings). The production pass is a Swift command-line tool built on SwiftSyntax and cached in `.build`;
the original application files are never changed in place. See
[`EMBEDDED_SOURCE_LOWERING.md`](EMBEDDED_SOURCE_LOWERING.md).

The same pass lowers `@Observable` stored members to property-scoped
`@Published` sources. Embedded Swift routes a mutation through a direct
source-to-StateStore index, while the StateStore's dependency graph owns the
source-to-render-owner edges.
Fiber targets a retained owner subtree when the dependency is unique; shared
or unowned sources retain the conservative root reconciliation path.

StateStore and FiberTree also expose an idempotent renderer-only `_dispose()`
boundary. Browser/session hosts call it before replacing a root tree so
observation callbacks, tasks, subscriptions and source-index entries are
detached while the renderer is quiescent; `deinit` remains the native safety
net. Runtime counters are available as named diagnostics rather than forcing
hosts to depend on the ordering of a raw counter array.

The complete source/owner, fallback, coalescing and teardown semantics are
specified in [`OBSERVATION_CONTRACT.md`](OBSERVATION_CONTRACT.md). That
contract is covered by the dependency graph tests, Fiber tests and the
real Embedded lowering/browser fixture.

## Semantic subsystems

The shared Fiber/BrowserIO chain is also the authority for the major
cross-cutting behaviors:

- identity and reconciliation: [`ReconciliationIdentityTests.swift`](../Tests/SwiftUIWebTests/ReconciliationIdentityTests.swift)
- layout: [`Architecture/CSS_LAYOUT.md`](Architecture/CSS_LAYOUT.md)
- scrolling: [`test-scrolling-browser.mjs`](../Tools/test-scrolling-browser.mjs)
- presentations and focus: [`PresentationFocusTests.swift`](../Tests/SwiftUIWebTests/PresentationFocusTests.swift)
- controls: [`ControlSemanticsTests.swift`](../Tests/SwiftUIWebTests/ControlSemanticsTests.swift)
- accessibility: [`AccessibilityBackendTests.swift`](../Tests/SwiftUIWebTests/AccessibilityBackendTests.swift)
- performance contracts: [`Performance/PERFORMANCE_CONTRACTS.md`](Performance/PERFORMANCE_CONTRACTS.md)

The executable tests are the source of truth for those focused contracts;
historical migration reports and one-off validation dumps are intentionally
not part of the architecture.

## BrowserIO, networking and storage boundary

Browser capabilities use one host-neutral Swift surface. `URLSession` keeps
the async/await API and request/response value types in
`SwiftUIWebNetworking`; the browser implementation delegates to
`BrowserHTTPClient` and `fetch`, while native builds install the isolated
`NativeNetworkAdapter`. Timeout scheduling, cancellation and response-stream
cleanup are owned by the host operation token, so application code does not
need platform branches or callback wrappers.

`BrowserIO` is also the ownership boundary for timers, byte buffers, DOM/media
handles and storage operations. Every asynchronous operation has a terminal
completion, cancellation aborts its controller/reader/transaction, and
disposing a host releases listeners, open IndexedDB connections and result
buffers. Web Storage revisions are monotonic 64-bit values; batches support
optimistic expected-revision checks and rollback on quota/security failures.
IndexedDB records carry an explicit schema version, durable migrations and
quota preflight. `StorageRuntime` invalidates its read cache on reload or
cross-tab events and exposes typed transaction errors without leaking browser
types into Core. `make embedded-network-storage-test` covers the host with a
fake IndexedDB (`Tools/BrowserIO/test-host.mjs`) and, in a real browser,
download progress and the persistence of `localStorage` and IndexedDB records
across a page reload (`Tools/test-browserio-persistence.mjs`, which drives
`Tools/BrowserIO/browser-smoke.html`; `make embedded-network-storage-browser`
serves the same page for a manual look).

BrowserIO operation identifiers are defined once in
[`BrowserIO/PROTOCOL.json`](BrowserIO/PROTOCOL.json) and generated into the
Swift and JavaScript hosts. `make tools-test` runs the generator in check mode
and rejects stale constants before a build can publish a bundle. Response
headers containing `Set-Cookie` are deliberately kept inside the browser
cookie jar and never cross this boundary into Swift state, render nodes or
diagnostics.

Foundation is not re-exported by the `SwiftUIWeb` façade. Native
`UserDefaults`, `Data` and `URLSession` parity lives in explicitly native
adapter files; the Embedded/WASI path uses the same public names backed by
JavaScript host primitives.

## Canonical developer workflow

```sh
make setup
make run
make test
make wasm-size
make clean
```

More focused browser, conformance and performance commands are listed in
[`DEVELOPMENT_WORKFLOW.md`](DEVELOPMENT_WORKFLOW.md). The layout oracle and
component catalog remain executable tests; generated reports belong under
`.build/` and are not architecture documentation.
