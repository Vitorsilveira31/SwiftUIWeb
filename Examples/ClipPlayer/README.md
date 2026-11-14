# Video

A video player that plays three public clips, two progressive MP4 and HLS streams, with transport controls, a scrubber, playback speed, mute and volume, and a note field. It presses on `VideoPlayer(player:)` from AVKit, an `AVPlayer` owned by an `@Observable` view model, `NotificationCenter.notifications(named:)` in `.task` for looping and playback failure, and a `GeometryReader` that picks a side column on wide screens.

```
Sources/ClipPlayer/
  App/          ClipPlayerRootView.swift             the entry point and NavigationStack
  Core/         Strings.swift, ClockText.swift       user-visible text, m:ss formatting
  Data/         Clip, ClipRepository, SampleClipRepository
  Features/Player/
    PlayerViewModel.swift                            State, Action, owns the AVPlayer
    Views/                                           the screen and its controls
```

iOS: open `Darwin/ClipPlayer.xcodeproj` in Xcode and run the scheme "ClipPlayer App".

Browser: run `make example-web EXAMPLE=ClipPlayer` from the repository root.
