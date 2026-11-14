# Photo Editor

A photo on a gesture surface: pinch to zoom, two fingers to turn, drag to pan, and drag the crop corners. Preset filters,
adjustment sliders, undo, export through `ImageRenderer` and `ShareLink`, and a print-order form. Camera and save sheets
show what SwiftUI cannot do on this platform.

It presses on `MagnifyGesture`, `RotateGesture`, `DragGesture` with `@GestureState`, `Canvas`, the colour and blur
modifiers, `PhotosPicker`, `ImageRenderer`, `ShareLink`, `Form` and `ContentUnavailableView`.

```
Sources/PhotoEditor/
  App/             PhotoEditorRootView (NavigationStack and title)
  Core/            Strings, Int dollar formatting
  Data/            Edit, Crop, Corner, Adjustment, Preset, PrintSize, Country, ShippingOption, PlacedOrder
  Features/
    Editor/        EditorViewModel, PhotoExporter, EditorSheet
      Views/       screen, surface, stage, crop overlay and handle, sliders, action grid, sample art
    Sheets/Views/  camera, recents and save sheets
    PrintOrder/    PrintOrderViewModel
      Views/       print sheet, form and its sections
```

Run on iOS: open `Darwin/PhotoEditor.xcodeproj` and choose the scheme "PhotoEditor App".

Run in the browser: `make example-web EXAMPLE=PhotoEditor` from the repository root.
