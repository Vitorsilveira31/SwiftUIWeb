# CanvasGallery

A gallery of 32 Canvas drawing fixtures in five pages, one tile per fixture, with a step counter and a
backdrop switch. It presses on `Canvas` with `GraphicsContext` (paths, strokes, clips, blend modes, layers,
gradients, text and images), and on `Picker` (segmented), `LazyVGrid` with adaptive columns, `Toggle` and
`Button`, driven by an `@Observable` view model.

```
Sources/CanvasGallery/
  App/        CanvasGalleryRootView (NavigationStack, title)
  Core/       Strings, Palette (colours, gradients), Paths (path builders), CanvasText, TileMetrics
  Data/       Fixture (the 32-entry catalog), GalleryPage (five pages)
  Features/Gallery/
    GalleryViewModel.swift
    Views/    GalleryView, GalleryControlRow, FixtureTile
    Painters/ Shapes/ Paint/ Sequences/ Typography/ Pictures/   one painter per fixture
```

Run on iOS: open `Darwin/CanvasGallery.xcodeproj` and run the scheme "CanvasGallery App".
Run in the browser: `make example-web EXAMPLE=CanvasGallery` from the repository root.
