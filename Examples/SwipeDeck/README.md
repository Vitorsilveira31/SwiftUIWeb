# SwipeDeck

A stack of profile cards that the user drags left, right or up, or throws with round buttons; undo brings the last card back and a like that matches shows a "It's a match!" overlay. It presses on `DragGesture` with `predictedEndTranslation`, `ZStack` ordering, `gesture(_:including:)`, `GeometryReader`, `ContentUnavailableView`, and an `@Observable` view model.

```
Sources/SwipeDeck/
├── App/
│   └── SwipeDeckRootView.swift          NavigationStack and title
├── Core/
│   └── Strings.swift                    every user-visible string
├── Data/
│   ├── Decision.swift                   like, nope, super like; the release verdict
│   ├── Profile.swift
│   ├── ProfileRepository.swift          protocol
│   └── SampleProfileRepository.swift    eight sample people
└── Features/SwipeDeck/
    ├── SwipeDeckViewModel.swift         State, Action, send(_:)
    ├── DeckLayout.swift                 sizes derived from the stage
    ├── DeckMotion.swift                 the one spring
    └── Views/                           screen, stage, card, stamps, buttons, overlay
```

Run on iOS: open `Darwin/SwipeDeck.xcodeproj` and pick the scheme "SwipeDeck App".

Run in the browser: `make example-web EXAMPLE=SwipeDeck` from the repository root.
