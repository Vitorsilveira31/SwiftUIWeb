# TextStudies

Seven studies of text laid out before it is drawn: text flowing around moving shapes and a draggable dragon, masonry cards whose heights are known before placement, a 1,200-card occlusion wall, balanced columns, an editorial spread, and ASCII art. The app presses on `Canvas` with `GraphicsContext.resolve(Text).measure(in:)`, `TimelineView(.animation(minimumInterval:paused:))`, `DragGesture`, custom `Layout` types (`sizeThatFits`, `placeSubviews`, `LayoutSubview.place`), and `Picker`, `Slider` and `ScrollView`.

```
Sources/TextStudies/
  App/            root view and its ViewModel (selected study, clock, text)
  Core/           Strings, and Core/TextFlow: line breaker, column balancer, obstacles, width cache, clock
  Data/           studies catalog, text repository protocol, sample prose, card generator
  Features/
    Shared/       Eyebrow, CardView, MasonryLayout, FlowLayout
    Balls/        Views/ (study view, scene painter)
    Dragon/       Views/ (study view, silhouette and painter)
    Masonry/      MasonryViewModel, Views/
    Magazine/     Views/
    Ascii/        AsciiFace, Views/ (study view, painter)
    Wall/         Views/
    Spread/       Views/ (study view, drop cap, pull quote, round picture)
```

Run on iOS: open `Darwin/TextStudies.xcodeproj` and pick the scheme "TextStudies App".
Run in the browser: `make example-web EXAMPLE=TextStudies` from the repository root.
