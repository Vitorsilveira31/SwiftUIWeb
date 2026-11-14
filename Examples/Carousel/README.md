# Carousel

A Cards screen with a strip of 25,000 cards and a vertical feed of 200 posts, some holding their own horizontal strips and message inboxes. It presses on `ScrollView` with `LazyHStack` and `LazyVStack`, `scrollTargetLayout()` with `scrollPosition(id:)` for programmatic jumps, and toolbar groups in both the primary and bottom bars.

```
Sources/Carousel/
  App/CarouselRootView.swift          entry point, wraps the screen in a NavigationStack
  Core/Strings.swift                  user-visible text
  Data/                               CardVO, PostVO, CardsRepository, SampleCardsRepository
  Features/Cards/CardsViewModel.swift state and actions for the screen
  Features/Cards/Views/               CardsView, strip, feed, inbox and card views
```

iOS: open `Darwin/Carousel.xcodeproj` and run the scheme "Carousel App".
Browser: `make example-web EXAMPLE=Carousel` from the repository root.
