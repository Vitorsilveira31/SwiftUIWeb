# Motion Gallery

A gallery of 15 small animations, one 64x64 tile each: seven image tiles drawn from six quarter-square
frame sequences, and eight keyframe-style tiles, with a shimmer loading skeleton on a second page. Restart replays every tile.
It presses on `repeatForever` animations, `PhaseAnimator`, `KeyframeAnimator` with `KeyframeTrack`,
`TimelineView` (periodic and animation schedules), `rotationEffect(anchor:)` and `LazyVGrid`.

```
MotionGallery/Sources/MotionGallery/
  App/        MotionGalleryRootView.swift            the NavigationStack and title
  Core/       Strings.swift, Palette.swift
  Data/       GalleryCatalog.swift, GalleryEntry.swift, FrameSequence.swift
  Features/Gallery/
    GalleryViewModel.swift                           page and restart counter
    Views/     GalleryView, FixturesPage, GallerySection, GalleryCell, GalleryTile
      Frames/     FrameTile, QuarterFrame, QuarterCell
      Keyframes/  Sweep, Pulse, Rotation, Glow, Steps, Tour, Origin, Held tiles
      Shimmer/    ShimmerPage, ShimmerRow, ShimmerBar
```

Run on iOS: open `Darwin/MotionGallery.xcodeproj` and run the scheme "MotionGallery App".
Run in the browser: `make example-web EXAMPLE=MotionGallery` from the repository root.
