import SwiftUIWebCore
@_spi(WebMount) import SwiftUIWebBrowser

/// MapLibre GL JS is intentionally hidden behind this file. Applications only
/// see Map/Marker/MapProvider values; they never need to import JavaScript interop,
/// know a MapLibre class name, or manage a map instance themselves.
@MainActor enum MapLibreBackend {
  static let mountKey = "maplibre-mount"
  private static var registration: WebSubscription?

  static func installIfNeeded() {
  }
}

