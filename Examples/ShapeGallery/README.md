# Shape Gallery

A gallery of 52 static vector fixtures in ten pages, each a 120 x 80 picture named by its `fx-*` identifier. It presses on `Path`, custom `Shape` types, gradients, `mask`, `clipShape`, blend modes and filter modifiers, `transformEffect` and `rotationEffect`, `Canvas`, and text placed by anchor and baseline.

```
Sources/ShapeGallery/
  App/                      ShapeGalleryRootView (NavigationStack, title)
  Core/                     Strings, Color(hex:), placement and layer modifiers, SVG transforms, gradient stops
  Data/                     GalleryPage (ten pages), GalleryCatalog (fixtures per page)
  Features/Gallery/
    GalleryView, HitTestViewModel
    Shapes/                 Star, Heart, Ring, TwoDiscs, Arrowhead, DotField, Checkers, Hatching
    Views/                  FixtureTile, FixtureGrid, GalleryPageContent
    Views/Page01 ... Page10 one folder per page: Page0NView and one FxName.swift per fixture
```

Run on iOS: open `Darwin/ShapeGallery.xcodeproj` and pick the scheme "ShapeGallery App".

Run in the browser: `make example-web EXAMPLE=ShapeGallery` from the repository root.
