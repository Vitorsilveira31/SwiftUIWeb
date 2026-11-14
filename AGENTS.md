# Contributor guidelines

The rules every change to SwiftUIWeb follows, whether a person or a coding agent writes it: where code goes, what the
framework may depend on, and how components are styled. The last sections route coding agents to the project's skills.

## Default Project Settings

The repository is Swift and JavaScript only. It needs no other toolchain: the runtime and the source lowerer
(`Tools/SwiftUIWebLowering`) are Swift, and the host, tests, audits and build scripts are JavaScript run by `bun`.

## Implementation Placement and Runtime Boundaries

Choose the implementation layer by responsibility. The product has two layers:

1. **Swift for the public API, the runtime and orchestration.** Swift owns the SwiftUI-shaped API, app-facing types,
   view composition, the Fiber tree (identity, child matching, the structural arena, dependencies and observation),
   structured concurrency, and the deterministic logic of the framework (serialization, ISO 8601, JSON, mutation
   buffers). There is no native runtime library behind it: no C ABI to keep in step.
2. **JavaScript for browser-host capabilities.** Put DOM operations, `fetch`, storage, media, observers, timers,
   and other APIs that only exist in the browser in JavaScript. Keep this layer a thin host adapter; do not move
   application or domain logic into JavaScript. Pure computations that the browser can answer better than Swift
   (NSPredicate evaluation, number formatting, string folding) are JavaScript host operations behind BrowserIO.

Use the smallest boundary that matches the feature:

- browser-only capability or computation the browser provides: `Swift API -> JavaScript host -> Swift`;
- pure shared computation: Swift.

Keep the JavaScript interface narrow and explicit. Do not add a JavaScript layer merely to avoid a small amount of
Swift.

Framework modules are Foundation-free on every host, including `WebFoundation`,
Core, Fiber, and browser/runtime targets. There is one implementation of each
Foundation-shaped type, SwiftUIWeb's own, on macOS, Linux, WASI and the
browser:

- never import or branch on Apple's Foundation, UniformTypeIdentifiers,
  Combine, CoreGraphics, CryptoKit or any other Apple framework in `Sources/`
  (`#if canImport(Foundation)` is not a way to mean "native");
- operating-system capabilities (locks, threads, the clock) belong in the libc
  adapter `SwiftUIWebLocking` (`RuntimeLock.swift`, `HostThreads.swift`,
  `HostClock.swift`), behind `canImport(Darwin)`/`Glibc`/`Musl`;
- `hasFeature(Embedded)` separates the Embedded language subset from full
  Swift; it is not a host switch.

Applications must not need platform `#if` branches for behavior that the
framework can hide behind these runtime boundaries. The native build must keep
compiling and passing its tests on Linux (`swift build --build-tests` and
`swift test` in the `swift:6.4` image).

### Tooling Languages

Code outside the product (tests, audits, build and release scripts under `Tools/`) is JavaScript run by `bun`,
or Swift. Do not add Python: new tooling is JavaScript or Swift.

- **Browser tests are Node/bun Playwright** (`Tools/test-*.mjs`). Start from
  `Tools/browser-test-support.mjs`, which picks the engine (`SWIFTUIWEB_BROWSER_ENGINE`), the Chromium
  binary (`CHROMIUM_PATH`) and serves a built bundle.
- **The source lowerer is the Swift package `Tools/SwiftUIWebLowering`** (SwiftSyntax), built and cached by `Tools/swiftuiweb-lowering.sh`.
  Use JavaScript for scripts that mostly drive a browser, Node APIs or text.
- **There is no Python in the repository, and the build needs no Python installation.** Tests, audits and
  build scripts are JavaScript (`Tools/*.mjs`, run by `bun`; the small build tools sit behind
  `Tools/swiftuiweb-tools.sh`) or Swift (the source lowerer). Do not add a `.py` file or a `python3` call, in a script, a
  Makefile target, a package script or a document that tells someone to run one. The third-party skills
  under `.agents/skills` are the only exception.

### Canonical Product Profile

The canonical SwiftUIWeb product is an Embedded Swift/WebAssembly browser
application backed by the Swift runtime and JavaScript host adapters. Native
SwiftPM builds exist for package tooling, source lowering, tests, diagnostics,
and development ergonomics; they are not a reason to make application code
carry a second runtime model.

Conditional compilation is therefore an implementation-boundary tool, not an
application design pattern:

- do not add `#if os(...)`, `#if arch(...)`, `#if canImport(...)`, or
  `#if hasFeature(Embedded)` to consumer applications for behavior the
  framework can own;
- keep unavoidable conditions in the smallest low-level adapter, and prefer a
  single host-neutral API over parallel native/WASI/Embedded call sites;
- use `#if hasFeature(Embedded)` only where the compiler or ABI genuinely
  differs, such as Embedded serialization, exports, or runtime hooks;
- treat broad `arch(wasm32)` and `os(WASI)` checks as suspicious: verify that
  they are really required for the canonical Embedded profile before adding
  them;
- remove compatibility branches that only preserve an abandoned runtime
  model instead of preserving them indefinitely.

When cleaning a feature, keep shared logic in Swift, put browser-only effects in
JavaScript, and leave the application with the public typed facade. Validate the
Embedded browser path after the cleanup; a successful native build alone is not
sufficient evidence.

## Component Styling: Fixed Base, Modifiers Only Adjust

SwiftUIWeb follows SwiftUI here: a component's look is fixed by the framework, and a view
modifier adjusts it at specific points without redefining it.

- **The base is `Tools/styles.css`.** Each component has one base rule that keeps it looking
  the same everywhere. `Tools/lint-styles.mjs` fails when a later rule makes a declaration
  dead. Class names and `data-*` attributes are internal.
- **A modifier adjusts.** It may write an inline value, a custom property or a `data-*`
  attribute on the node, or select a variant the base already defines (the way a
  `ButtonStyle` picks a look). It must keep the component's base class on the node and must
  not replace, remove or redefine the component's look, and it must not need `!important`.
- **A new look is a new component or variant in the base,** not an edit that changes an
  existing component for every user. Changing a base rule is a deliberate visual change:
  check it with a before/after render comparison and note it in `Documentation/MIGRATION.md`.
- **Application skins do not belong in `Tools/styles.css`.** Example apps style themselves
  through the public API and tokens.
- **`!important` in the base is reserved for framework-owned behavior** that must beat an
  inline value: `[hidden]`, `prefers-reduced-motion`, the compact/regular switch
  (`responsive-*`), the narrow `NavigationSplitView` collapse, and protocol state such as
  `data-scroll-disabled`. Any other use needs a reason in a comment.
- **Applications** restyle through the tokens listed in `Documentation/BROWSER_APP_SHELL.md`.
  Overriding internal classes is allowed but is the application's own risk.

## Core Capabilities

### 1. Question Routing
Route questions to the project skills:
- Swift `async`/`await`, `Sendable`, actors, or isolation → `swift-concurrency`
- WASI, WebAssembly, Embedded Swift, or conditional compilation → `swift-wasm-porting`
- Browser fixtures, DOM/focus/presentation/scrolling tests → `browser-validation`
- WASM size, link maps, reachability, or release budgets → `wasm-release-audit`
- BrowserIO, Embedded browser interop, or real browser host behavior → invoke `browser-validation`
- Real browser automation from the terminal → `playwright`
- Repository threat modeling or abuse-path analysis → explicitly invoke `security-threat-model`
- SwiftUI-shaped API and view composition → explicitly invoke `swiftui-expert`

## Skill Files

For detailed guidance, see:
- `.agents/skills/swift-concurrency/SKILL.md` - Swift concurrency
- `.agents/skills/swift-wasm-porting/SKILL.md` - Swift WASM/Embedded compatibility
- `.agents/skills/browser-validation/SKILL.md` - Browser and Embedded validation
- `.agents/skills/wasm-release-audit/SKILL.md` - WASM release audits
- `.agents/skills/playwright/SKILL.md` - Terminal browser automation
- `.agents/skills/security-threat-model/SKILL.md` - Repository threat modeling
