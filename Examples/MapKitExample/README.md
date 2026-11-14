# MapKitExample

A map from `SwiftUIWebMapKit` with the MapKit-shaped API: a camera position, a marker, an annotation, a polyline, a polygon, map
controls and a tag selection. The default map needs no key. It uses an OpenStreetMap-compatible style, and MapLibre GL JS is fetched
only when the map is rendered.

```sh
make run map                  # build and serve it (it prints the address)
```

The map is centered on São Paulo. Tapping the marker tagged `sao-paulo` writes its tag into `selection`, and the text under the map
shows it. Camera changes are written back into `position`, so the state follows the map when the user pans or zooms.

What to look at in `main.swift`:

- `MapCameraPosition.region(...)` and `onMapCameraChange`, which keep the camera in state.
- `Marker`, `Annotation`, `MapPolyline` and `MapPolygon` inside `Map`, with `.mapTag` for selection.
- `ProviderExamples`, which lists the other providers (a self-hosted style, PMTiles, MapTiler and Stadia Maps) and how to pass one
  with `.mapConfiguration(_:)`. Only `keyless` is used by default; the others need a key or a server of your own.
