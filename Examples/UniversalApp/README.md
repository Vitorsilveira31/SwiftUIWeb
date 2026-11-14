# UniversalApp: Darwin + SwiftUIWeb

This example keeps one SwiftUI-shaped screen in `Sources/Shared` and gives
each host only its entry point and host-specific chrome:

```text
UniversalApp/
├── Darwin/
│   └── UniversalApp.xcodeproj/       # iOS + iPadOS target
├── Web/                              # BrowserApp entry point
├── Sources/Shared/                    # shared model, state and views
├── Package.swift                      # SwiftUIWeb web package
└── project.xcworkspace/              # opens the Darwin project in Xcode
```

The shared layer uses one import boundary: the web package defines
`WEB`, while the Xcode target uses Apple's `SwiftUI`. No view or
state logic branches on device, browser, or viewport.

`SettingsHoverAdapter` applies `.hoverEffect(.highlight)` only to full-row
actions: clicking anywhere on the row performs the same action. Rows with a
switch only respond through the switch and are not highlighted as a whole.
The default highlight changes the background without hover or press scaling.
Apps that want a scale can opt in through the phase-aware
`.hoverEffect { effect, isActive, proxy in ... }` closure; the framework tests
cover both the neutral default and custom scale values.

The sample reproduces the Settings shell from iPhone/iPad: account card,
connectivity and system sections, Wi‑Fi detail, grouped rows, toggles and
adaptive navigation. `TabView` with `.sidebarAdaptable` is the only shell in
the shared source. Native SwiftUI chooses its own iPhone/iPad presentation. In
the browser, phone widths use a bottom tab bar, tablet widths use a collapsed
icon rail that can expand on demand, and wide desktop windows show the labeled
sidebar by default. Panels remain mounted, so changing size does not reset
selection, scroll position, focus, or local control state.

## iOS and iPadOS

Open [`project.xcworkspace`](project.xcworkspace) in Xcode and run the
`UniversalApp` scheme on an iPhone or iPad simulator. The target is iOS 18 and
uses `TabView` with `.sidebarAdaptable`: iPhone uses a bottom tab bar, while
iPadOS adapts tab navigation to the available space. The collapsed icon rail
is a browser-only responsive treatment for tablet-sized web windows.

The equivalent headless validation is:

```sh
cd ../..
make universal-app-test
```

This builds the iOS Simulator target and the Embedded browser product from the
same shared source. The CI runs this gate as well.

## SwiftUIWeb

From this directory, build the web product with the official command:

```sh
swift package plugin swiftuiweb --path . --product UniversalWebApp
```

For a local browser server during development:

```sh
SWIFTUIWEB_ROOT=../.. \
  swift ../../Tools/swiftuiweb-run.swift \
  --path . --product UniversalWebApp --port 8080
```

The launcher owns the free-port choice, Bun lifecycle and Ctrl-C cleanup. The
web entry point is only `Web/UniversalWebApp.swift`; the screen itself remains
the shared `SharedRootView`.
