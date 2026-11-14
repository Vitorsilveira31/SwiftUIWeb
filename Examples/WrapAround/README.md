# Wrap Around

Seven studies in type: body text flows around moving shapes, discs, a figure, a triangle and a drop cap, and
the words make room line by line. It presses on a custom SwiftUI `Layout` (`WrapFlowLayout`, with a
`LayoutValueKey` marking paragraph breaks), `TimelineView(.animation(paused:))` for the clock, `DragGesture`
on draggable discs, and an `@Observable` view model.

```
Sources/WrapAround/
  App/                  WrapAroundRootView (NavigationStack, navigation title)
  Core/Strings.swift    every user-visible string
  Core/Flow/            WrapFlowLayout, WrapBreakKey, WrapExclusion, WrapCaption
  Data/Models/          WrapScene, WrapTint, WrapOrb, WrapWord
  Data/Scenes/          one geometry per study behind WrapSceneGeometry (+ WrapSceneContext, WrapSpace)
  Data/Copy/            WrapCopyRepository, FixtureWrapCopy, the prose (WrapCopy, WrapText, WrapStudyText)
  Features/WrapAround/  WrapAroundViewModel, WrapMetrics
  Features/WrapAround/Views/   screen, header, chips, footer, study card, prose, shapes, orb handle
```

Run on iOS: open `Darwin/WrapAround.xcodeproj`, scheme "WrapAround App".
Run in the browser: `make example-web EXAMPLE=WrapAround` from the repository root.
