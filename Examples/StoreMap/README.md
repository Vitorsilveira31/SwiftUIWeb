# StoreMap

A Stores screen: a MapKit map with one pin per store, a row of buttons that select a store and move the camera, and zoom controls. It presses on `Map` with `MapCameraPosition`, `Marker`, `onMapCameraChange(frequency:)`, `MKCoordinateRegion`, and a `Binding` that separates pin taps from button selections.

```
Sources/StoreMap/
  App/            StoreMapRootView.swift          NavigationStack and the title
  Features/StoreMap/
    StoreMapScreen.swift, StoreMapViewModel.swift
    Views/        StoreMapHeader, StoreMapView, StoreMapControls, StorePickRow, StoreZoomRow
  Data/           StoreRepository (protocol), SampleStoreRepository, StoreVO
  Core/           MapZoom (zoom <-> span), Strings
```

Run on iOS: open `Darwin/StoreMap.xcodeproj` and run the scheme "StoreMap App".
Run in the browser: `make example-web EXAMPLE=StoreMap` from the repository root.
