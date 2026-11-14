import SwiftUIWeb
import SwiftUIWebBrowser
import SwiftUIWebMapKit

private enum ProviderExamples {
  static let keyless = MapConfiguration()
  static let selfHosted = MapConfiguration(provider: .selfHosted(styleURL: "https://maps.example.com/style.json", attribution: "© Example Maps"))
  static let pmtiles = MapConfiguration(provider: .pmtiles(url: "/tiles/city.pmtiles", attribution: "© Example data"))
  static let mapTiler = MapConfiguration(provider: .mapTiler(apiKey: "YOUR_MAPTILER_KEY"))
  static let stadia = MapConfiguration(provider: .stadiaMaps(apiKey: nil))
}

/// A completely keyless map. The default provider is an OSM-compatible style;
/// MapLibre GL JS is fetched only because this view is actually rendered.
@main
struct MapKitExample: BrowserApp {
  @State private var position = MapCameraPosition.region(
    CoordinateRegion(
      center: CLLocationCoordinate2D(latitude: -23.5505, longitude: -46.6333),
      latitudeDelta: 0.12,
      longitudeDelta: 0.12
    )
  )
  @State private var selection: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("SwiftUIWebMapKit").font(.title)
      Text("Keyless OpenStreetMap-compatible tiles with configurable providers.")
        .foregroundStyle(.secondary)
      Map(position: $position, selection: $selection) {
        Marker("São Paulo", coordinate: CLLocationCoordinate2D(latitude: -23.5505, longitude: -46.6333))
          .mapTag("sao-paulo")
        Annotation("Pin", coordinate: CLLocationCoordinate2D(latitude: -23.56, longitude: -46.64)) {
          Text("★").padding(6).background(Color.white).cornerRadius(6)
        }
        MapPolyline([
          CLLocationCoordinate2D(latitude: -23.5505, longitude: -46.6333),
          CLLocationCoordinate2D(latitude: -23.56, longitude: -46.64)
        ]).stroke(.blue, lineWidth: 4)
        MapPolygon([
          CLLocationCoordinate2D(latitude: -23.54, longitude: -46.62),
          CLLocationCoordinate2D(latitude: -23.54, longitude: -46.60),
          CLLocationCoordinate2D(latitude: -23.56, longitude: -46.60),
          CLLocationCoordinate2D(latitude: -23.56, longitude: -46.62)
        ]).fill(.green.opacity(0.2)).stroke(.green)
      }
      .mapControls(compass: true, scale: true)
      .onMapCameraChange { change in position = .camera(change.camera) }
      .frame(height: 460)
      if let selection { Text("Selected: \(selection)") }
    }
    .padding(20)
  }
}

// `ProviderExamples.keyless` is used by default. External providers are opt-in
// and do not alter the compatible Map API:
//
// let selfHosted = MapConfiguration(provider: .selfHosted(
//   styleURL: "https://maps.example.com/style.json",
//   attribution: "© Example Maps"))
// let mapTiler = MapConfiguration(provider: .mapTiler(apiKey: "…"))
// let stadia = MapConfiguration(provider: .stadiaMaps(apiKey: nil))
// let pmtiles = MapConfiguration(provider: .pmtiles(url: "/tiles/city.pmtiles"))
// Map(position: $position) { ... }.mapConfiguration(selfHosted)
