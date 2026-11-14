# Trio: one Swift app for iOS, Android and the Web

A deliberately small app (a counter, a task list, an About screen) that shows the layout of the realistic examples: **one
package and one shared source tree** run natively on iOS (SwiftUI), on Android (Skip Fuse, Jetpack Compose) and in the
browser (SwiftUIWeb, Embedded Swift/WebAssembly). Only the entry points differ.

```text
Trio/
├── Package.swift            # Skip package by default; the SwiftUIWeb package when SWIFTUIWEB_EMBEDDED=1
├── Skip.env                 # app name, bundle id and versions shared by Darwin/ and Android/
├── Sources/Trio/            # the whole app, shared by the three hosts
│   ├── App/                 # TrioRootView (every host loads it), ContentView, the Skip app delegate
│   ├── Core/RuntimePlatform.swift   # the only platform check, so the About screen can say where it runs
│   ├── Data/                # TodoItem and TodoRepository (in memory)
│   ├── Features/            # Counter, Tasks, About: View -> ViewModel (State/Action/send) -> Repository
│   ├── Resources/           # string catalog and assets (Skip builds)
│   └── Skip/skip.yml        # native (Fuse) mode
├── Darwin/                  # Xcode host: Main.swift loads TrioRootView
├── Android/                 # Gradle host: Main.kt loads TrioRootView
└── Web/                     # BrowserApp host: TrioWebApp.swift loads TrioRootView, Resources/head.html
```

## How one package serves three hosts

`Package.swift` returns one of two packages:

- **Skip (default).** A dynamic library `Trio` with the `skipstone` plugin. Xcode builds it for iOS, and the same Xcode
  build (or Gradle) cross-compiles it for Android.
- **Web (`SWIFTUIWEB_EMBEDDED=1`, which SwiftUIWeb's launcher sets).** The same `Sources/Trio` against SwiftUIWeb, with
  the `WEB` flag and module aliases `SwiftUI=SwiftUIWeb` and `Foundation=WebFoundation`, so the shared files keep
  `import SwiftUI` and `import Foundation`. The Skip-only files (`Skip/`, `Resources/`, `App/TrioAppDelegate.swift`)
  are excluded, and `Web/` adds the `BrowserApp` entry point.

The view models import `Observation` and `SkipFuse` only under `#if !WEB`: Skip Fuse needs them to bridge
`@Observable` to Compose, and SwiftUIWeb brings its own observation.

## Run it

Web (from the repository root):

```sh
make trio-web            # build and serve
make trio-browser-test   # build and check it in Chromium
```

iOS: open `Examples/Trio/Project.xcworkspace` in Xcode and run the **Trio App** scheme on a simulator. With the Android
emulator running, the same build launches the Android app too (`SKIP_ACTION` in `Darwin/Trio.xcconfig`: `launch`,
`build` or `none`).

Android only: `skip android build` from `Examples/Trio`, or open `Android/` in Android Studio.

Requirements: Xcode, the Skip CLI (`brew install skiptools/skip/skip`, then `skip checkup`) and the Android SDK for
Android; the Embedded Swift WebAssembly SDK for the web (see the repository README).
