# Pocket OS

A phone operating system's face in one app: a lock screen with a live clock and a notification stack, a home screen with widgets, tiles and a dock, Messages with a pinned streaming assistant, a Reader library, and Settings. Apps open by zooming out of their tile.

It presses on `TimelineView`, `matchedGeometryEffect` with a shared `Namespace`, `PhaseAnimator`, `AsyncStream` with cancellation through `onTermination`, `scrollPosition(id:anchor:)` with `defaultScrollAnchor(.bottom)`, `safeAreaInset` for the composer, and `@AppStorage` for Settings.

```
Sources/PocketOS/
  App/                 PocketOSRootView: the NavigationStack, the Lock toolbar, appearance
  Core/                Strings (all user-visible text), Voice (fonts), ReadingScaleKey
  Data/                value types, repository protocols, sample and scripted implementations
  Features/
    Shell/             ShellViewModel (phases, apps, toast), ShellView, AppScreen, HomeBar
    LockScreen/        LockScreenViewModel, the lock views
    Home/              HomeViewModel, the home views, widgets, dock
    Messages/          MessagesViewModel (threads, streaming reply), inbox and thread views
    Reader/            ReaderViewModel, library and article views
    Settings/          no view model: @AppStorage lives in the sections
    Shared/            StatusBar and Wallpaper, used by more than one feature
```

Run on iOS: open `Darwin/PocketOS.xcodeproj` in Xcode and run the scheme "PocketOS App".

Run in the browser: from the repository root, `make example-web EXAMPLE=PocketOS`.
