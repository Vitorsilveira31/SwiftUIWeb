import Testing
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
import SwiftUIWebMapKit

@Suite
@MainActor
struct MapKitRenderingContractTests {
  private let context = _RenderContext(path: [_FiberKey("map-test")])

  @Test
  func coordinateRegionCameraPositionAndInteractionModesPreserveTheirShape() {
    let center = CLLocationCoordinate2D(latitude: -23.55, longitude: -46.63)
    let span = CoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.18)
    let region = CoordinateRegion(center: center, span: span)
    let compatibilityRegion = CoordinateRegion(
      center: center,
      span: CLLocationCoordinate2D(latitude: 0.12, longitude: 0.18)
    )

    _expectEqual(region, compatibilityRegion)
    _expectEqual(MapCameraPosition.region(region).region, region)
    _expectNil(MapCameraPosition.automatic.region)
    _expectNil(MapCameraPosition.userLocation.region)

    let camera = MapCamera(centerCoordinate: center, distance: 500, heading: 90, pitch: 20)
    let cameraPosition = MapCameraPosition.camera(camera)
    _expectEqual(cameraPosition.region?.center, center)
    _expectEqual(cameraPosition.region?.span.latitudeDelta, 0.1)
    _expectEqual(MapCameraPosition.userLocation(followsHeading: true, fallback: cameraPosition), .userLocation)

    let modes: MapInteractionModes = [.pan, .rotate, .pitch]
    _expectEqual(modes.rawValue, 13)
    _expectTrue(modes.contains(.pan))
    _expectFalse(modes.contains(.zoom))
    _expectEqual(MapInteractionModes.all.rawValue, 15)
    _expectEqual(MapCameraChangeFrequency.onEnd.rawValue, "onEnd")
    _expectEqual(MapCameraChangeFrequency.continuous.rawValue, "continuous")
  }

  @Test
  func defaultMapProducesAccessibleKeylessOpenStreetMapFallback() {
    let node = Map()._render(in: context)
    _expectTrue(node.classes.contains("mapkit-view"))
    _expectEqual(node.attributes["role"], "application")
    _expectEqual(node.attributes["aria-label"], "Map")
    _expectEqual(node.attributes["data-web-mount-key"], "maplibre-mount")
    _expectEqual(node.attributes["data-map-camera"], "{\"kind\":\"automatic\"}")
    _expectEqual(node.attributes["data-map-interaction-modes"], "15")
    _expectEqual(node.attributes["data-map-shows-compass"], "false")
    _expectEqual(node.attributes["data-map-shows-scale"], "false")
    _expectEqual(node.attributes["data-map-attribution"], "© OpenStreetMap contributors")
    _expectTrue(node.attributes["data-map-style-json"]?.contains("tile.openstreetmap.org") == true)
    _expectNil(node.attributes["data-map-authentication"])
  }

  @Test
  func regionAndCameraBindingsRenderFiniteCameraMetadata() {
    let center = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
    let region = CoordinateRegion(center: center, latitudeDelta: 0.2, longitudeDelta: 0.3)
    let regionMap = Map(coordinateRegion: .constant(region), interactionModes: [.pan, .zoom]) {}
    let regionNode = regionMap._render(in: context)
    _expectEqual(regionNode.attributes["data-map-center"], "47.6,-122.3")
    _expectEqual(regionNode.attributes["data-map-interaction-modes"], "3")
    _expectTrue(regionNode.attributes["data-map-camera"]?.contains("\"kind\":\"region\"") == true)
    _expectTrue(regionNode.attributes["data-map-camera"]?.contains("\"latitudeDelta\":0.2") == true)

    let camera = MapCamera(centerCoordinate: center, distance: 700, heading: 45, pitch: 10, zoom: 12)
    let cameraNode = Map(position: .constant(.camera(camera)))._render(in: context)
    _expectTrue(cameraNode.attributes["data-map-camera"]?.contains("\"kind\":\"camera\"") == true)
    _expectTrue(cameraNode.attributes["data-map-camera"]?.contains("\"distance\":700.0") == true)
    _expectTrue(cameraNode.attributes["data-map-camera"]?.contains("\"zoom\":12.0") == true)
    _expectEqual(cameraNode.attributes["data-map-camera-frequency"], "onEnd")
  }

  @Test
  func mapConfigurationAndModifiersSelectSafeProviderMetadata() {
    let assets = MapAssetConfiguration(
      scriptURL: "/assets/maplibre.js",
      stylesheetURL: "/assets/maplibre.css",
      pmtilesProtocolURL: "/assets/pmtiles.js"
    )
    let pmtiles = Map()
      .mapConfiguration(MapConfiguration(
        provider: .pmtiles(url: "/maps/city.pmtiles", attribution: "© City data"),
        assets: assets,
        interactionModes: [.pan],
        showsCompass: true,
        showsScale: true,
        attribution: "© Override"
      ))
    let node = pmtiles._render(in: context)
    _expectEqual(node.attributes["data-map-library-url"], "/assets/maplibre.js")
    _expectEqual(node.attributes["data-map-stylesheet-url"], "/assets/maplibre.css")
    _expectEqual(node.attributes["data-map-pmtiles-protocol-url"], "/assets/pmtiles.js")
    _expectEqual(node.attributes["data-map-attribution"], "© Override")
    _expectEqual(node.attributes["data-map-interaction-modes"], "1")
    _expectEqual(node.attributes["data-map-shows-compass"], "true")
    _expectEqual(node.attributes["data-map-shows-scale"], "true")
    _expectTrue(node.attributes["data-map-style-json"]?.contains("pmtiles:///maps/city.pmtiles") == true)

    let controlsOnly = Map()
      .mapProvider(.stadiaMaps(style: "alidade_smooth"))
      .mapStyle(.satellite)
      .mapControls(compass: true)
      .mapInteractionModes(.rotate)
    let controlsNode = controlsOnly._render(in: context)
    _expectEqual(controlsNode.attributes["data-map-interaction-modes"], "4")
    _expectEqual(controlsNode.attributes["data-map-shows-compass"], "true")
    _expectEqual(controlsNode.attributes["data-map-shows-scale"], "false")
    _expectTrue(controlsNode.attributes["data-map-style-url"]?.contains("alidade_smooth") == true)
    _expectNil(controlsNode.attributes["data-map-authentication"])
  }

  @Test
  func authenticatedProviderCredentialsNeverAppearInRenderedMapMetadata() {
    let mapTiler = Map()
      .mapProvider(.mapTiler(style: "streets-v2", apiKey: "maptiler-private-key"))
      ._render(in: context)
    _expectEqual(mapTiler.attributes["data-map-style-url"], "https://api.maptiler.com/maps/streets-v2/style.json")
    _expectEqual(mapTiler.attributes["data-map-authentication"], "host-managed")
    _expectFalse(mapTiler.attributes.values.contains { $0.contains("maptiler-private-key") })

    let stadia = Map()
      .mapProvider(.stadiaMaps(style: "alidade_smooth", apiKey: "stadia-private-key"))
      ._render(in: context)
    _expectEqual(stadia.attributes["data-map-style-url"], "https://tiles.stadiamaps.com/styles/alidade_smooth.json")
    _expectEqual(stadia.attributes["data-map-authentication"], "host-managed")
    _expectFalse(stadia.attributes.values.contains { $0.contains("stadia-private-key") })

    let safeQuery = Map()
      .mapStyle(.custom(url: "https://maps.example/style.json?lang=en&access_token=secret&theme=dark"))
      ._render(in: context)
    _expectEqual(safeQuery.attributes["data-map-style-url"], "https://maps.example/style.json?lang=en&theme=dark")
    _expectFalse(safeQuery.attributes.values.contains { $0.contains("secret") })
  }

  @Test
  func customRasterConfigurationEscapesStyleJsonAndPreservesAttribution() {
    let tileURL = "https://tiles.example/{z}?style=\"night\"\n"
    let attribution = "Maps \\\n© Example"
    let map = Map()
      .mapConfiguration(MapConfiguration(
        provider: .rasterTiles(tileURL, attribution: attribution),
        attribution: nil
      ))
      ._render(in: context)
    let style = map.attributes["data-map-style-json"] ?? ""
    _expectTrue(style.contains("\\\"night\\\""))
    _expectTrue(style.contains("\\n"))
    _expectTrue(style.contains("© Example"))
    _expectEqual(map.attributes["data-map-attribution"], attribution)

    let directConfiguration = MapConfiguration(
      provider: .selfHosted(styleURL: "https://maps.example/style.json", attribution: "© Hosted"),
      style: .custom("https://styles.example/night.json?token=hidden")
    )
    let customStyle = Map().mapConfiguration(directConfiguration)._render(in: context)
    _expectEqual(customStyle.attributes["data-map-style-url"], "https://styles.example/night.json")
    _expectEqual(customStyle.attributes["data-map-attribution"], "© Hosted")
    _expectNil(customStyle.attributes["data-map-style-json"])
  }

  @Test
  func mapContentsAndOverlayModifiersRenderSemanticCoordinatesAndSelections() {
    let center = CLLocationCoordinate2D(latitude: 1.25, longitude: -2.5)
    let marker = Marker("Station", coordinate: center).tint(.red).mapTag("station-1")._render(in: context)
    _expectEqual(marker.attributes["data-map-feature"], "marker")
    _expectEqual(marker.attributes["data-map-title"], "Station")
    _expectEqual(marker.attributes["data-map-latitude"], "1.25")
    _expectEqual(marker.attributes["data-map-longitude"], "-2.5")
    _expectNotNil(marker.attributes["data-map-tint"])
    _expectNotNil(marker.attributes["data-map-selection"])
    _expectEqual(marker.children.count, 1)

    let annotation = Annotation("Pin", coordinate: center, anchor: .topLeading) {
      Text("★")
    }.mapTag(42)._render(in: context)
    _expectEqual(annotation.attributes["data-map-feature"], "annotation")
    _expectEqual(annotation.attributes["data-map-anchor"], "0.0,0.0")
    _expectNotNil(annotation.attributes["data-map-selection"])

    let plainMarker = Marker("Default", coordinate: center)._render(in: context)
    _expectNil(plainMarker.attributes["data-map-system-image"])
    _expectNil(plainMarker.attributes["data-map-tint"])
    _expectNil(plainMarker.attributes["data-map-selection"])

    let iconMarker = Marker("Train", systemImage: "tram", coordinate: center)._render(in: context)
    _expectEqual(iconMarker.attributes["data-map-system-image"], "tram")

    let coordinates = [center, CLLocationCoordinate2D(latitude: 3, longitude: 4)]
    let polyline = MapPolyline(coordinates).stroke(.green, lineWidth: 5)._render(in: context)
    _expectEqual(polyline.attributes["data-map-feature"], "polyline")
    _expectEqual(polyline.attributes["data-map-coordinates"], "1.25,-2.5;3.0,4.0")
    _expectEqual(polyline.attributes["data-map-line-width"], "5.0")

    let polygon = MapPolygon(coordinates)
      .fill(.yellow)
      .stroke(.black, lineWidth: 1)
      ._render(in: context)
    _expectEqual(polygon.attributes["data-map-feature"], "polygon")
    _expectEqual(polygon.attributes["data-map-line-width"], "1.0")
    _expectNotNil(polygon.attributes["data-map-fill"])
    _expectNotNil(polygon.attributes["data-map-stroke"])

    let circle = MapCircle(center: center, radius: 25)
      .fill(.orange)
      .stroke(.purple)
      ._render(in: context)
    _expectEqual(circle.attributes["data-map-feature"], "circle")
    _expectEqual(circle.attributes["data-map-radius"], "25.0")
    _expectNotNil(circle.attributes["data-map-fill"])
    _expectNotNil(circle.attributes["data-map-stroke"])

    let map = Map {
      Marker("Child", coordinate: center)
    }._render(in: context)
    _expectEqual(map.children.count, 1)
    _expectEqual(map.children[0].attributes["data-map-title"], "Child")
  }
}
