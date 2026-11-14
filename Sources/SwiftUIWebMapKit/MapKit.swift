@_exported import SwiftUIWebCore
@_exported import SwiftUIWebFeatures
@_exported import SwiftUIWebCoreLocation
@_spi(WebMount) import SwiftUIWebBrowser

/// Web-safe MapKit coordinate types. They are defined in this optional module
/// so SwiftUIWebCore remains completely mapping- and MapLibre-free.
public typealias MapCoordinate = CLLocationCoordinate2D

public struct CoordinateSpan: Hashable, Sendable {
  public var latitudeDelta: Double
  public var longitudeDelta: Double
  public init(latitudeDelta: Double, longitudeDelta: Double) { self.latitudeDelta = latitudeDelta; self.longitudeDelta = longitudeDelta }
}
public typealias MKCoordinateSpan = CoordinateSpan

public struct CoordinateRegion: Hashable, Sendable {
  public var center: CLLocationCoordinate2D
  public var span: CoordinateSpan
  public init(center: CLLocationCoordinate2D, span: CoordinateSpan) { self.center = center; self.span = span }
  /// Compatibility convenience for the early SwiftUIWeb map placeholder,
  /// which represented a span with the same latitude/longitude value shape.
  public init(center: CLLocationCoordinate2D, span: CLLocationCoordinate2D) {
    self.init(center: center, span: CoordinateSpan(latitudeDelta: span.latitude, longitudeDelta: span.longitude))
  }
  public init(center: CLLocationCoordinate2D, latitudeDelta: Double, longitudeDelta: Double) {
    self.init(center: center, span: CoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
  }
}
public typealias MKCoordinateRegion = CoordinateRegion
/// Neutral spelling for callers that model the visible map as a viewport.
public typealias MapViewport = CoordinateRegion

public struct MapCamera: Hashable, Sendable {
  public var centerCoordinate: CLLocationCoordinate2D
  public var distance: Double
  public var heading: Double
  public var pitch: Double
  /// The web renderer's zoom is retained when a browser camera event
  /// round-trips through a SwiftUI binding. It is optional so the
  /// MapKit-shaped initializer remains source-compatible.
  public var zoom: Double?
  public init(centerCoordinate: CLLocationCoordinate2D, distance: Double = 1_000, heading: Double = 0, pitch: Double = 0, zoom: Double? = nil) {
    self.centerCoordinate = centerCoordinate; self.distance = distance; self.heading = heading; self.pitch = pitch; self.zoom = zoom
  }
}

public enum MapCameraPosition: Hashable, Sendable {
  case automatic
  case region(CoordinateRegion)
  case camera(MapCamera)
  case userLocation
  public static func userLocation(followsHeading: Bool, fallback: MapCameraPosition = .automatic) -> Self { _ = followsHeading; _ = fallback; return .userLocation }
  public var region: CoordinateRegion? {
    switch self {
    case .region(let value): return value
    case .camera(let value): return CoordinateRegion(center: value.centerCoordinate, latitudeDelta: 0.1, longitudeDelta: 0.1)
    default: return nil
    }
  }
}

public struct MapInteractionModes: OptionSet, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let pan = Self(rawValue: 1)
  public static let zoom = Self(rawValue: 2)
  public static let rotate = Self(rawValue: 4)
  public static let pitch = Self(rawValue: 8)
  public static let all: Self = [.pan, .zoom, .rotate, .pitch]
}
public enum MapCameraChangeFrequency: String, Hashable, Sendable { case onEnd, continuous }
public struct MapCameraChangeContext: Hashable, Sendable {
  public let camera: MapCamera
  public let region: CoordinateRegion
  public init(camera: MapCamera, region: CoordinateRegion) { self.camera = camera; self.region = region }
}
public typealias MapCameraUpdateContext = MapCameraChangeContext

public enum MapStyle: Hashable, Sendable {
  case standard, satellite, hybrid
  case custom(url: String)
  public static func custom(_ url: String) -> Self { .custom(url: url) }
}

/// Provider infrastructure is scoped to SwiftUIWebMapKit. The default is
/// keyless OpenStreetMap-compatible tiles; all URLs and credentials are
/// replaceable for self-hosted, PMTiles, MapTiler, Stadia, or other providers.
public struct MapProviderConfiguration: Hashable, Sendable {
  public var styleURL: String?
  public var tileURLTemplate: String?
  public var attribution: String
  public var accessToken: String?
  public var protocolURL: String?
  public init(styleURL: String? = nil, tileURLTemplate: String? = nil, attribution: String = "", accessToken: String? = nil, protocolURL: String? = nil) {
    self.styleURL = styleURL; self.tileURLTemplate = tileURLTemplate; self.attribution = attribution; self.accessToken = accessToken; self.protocolURL = protocolURL
  }
}
public enum MapProvider: Hashable, Sendable {
  case openStreetMap
  case pmtilesSource(url: String, attribution: String)
  case mapTilerSource(style: String, apiKey: String)
  case stadiaMapsSource(style: String, apiKey: String?)
  case custom(MapProviderConfiguration)
  public static var osm: Self { .openStreetMap }
  public static func pmtiles(url: String, attribution: String = "PMTiles") -> Self { .pmtilesSource(url: url, attribution: attribution) }
  public static func mapTiler(style: String = "streets-v2", apiKey: String) -> Self { .mapTilerSource(style: style, apiKey: apiKey) }
  public static func stadiaMaps(style: String = "alidade_smooth", apiKey: String? = nil) -> Self { .stadiaMapsSource(style: style, apiKey: apiKey) }
  public static func selfHosted(styleURL: String, attribution: String = "") -> Self { .custom(MapProviderConfiguration(styleURL: styleURL, attribution: attribution)) }
  public static func rasterTiles(_ template: String, attribution: String) -> Self { .custom(MapProviderConfiguration(tileURLTemplate: template, attribution: attribution)) }
}
/// Optional web assets used by the private map renderer. The public type is
/// intentionally provider/backend-neutral; applications can point it at a
/// self-hosted bundle without knowing which renderer realizes the map.
///
/// The URLs only travel to the page as `data-map-*` attributes of the map's host element. The Embedded browser build
/// renders an OpenStreetMap frame and loads none of them; a MapLibre mount that an application (or a later framework
/// version) provides is what would fetch them. The defaults point at a public CDN, so a mount that does should pin the
/// files with Subresource Integrity or bundle them with the app and pass its own URLs here.
public struct MapAssetConfiguration: Hashable, Sendable {
  public var scriptURL: String
  public var stylesheetURL: String
  public var pmtilesProtocolURL: String?
  public init(scriptURL: String = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js", stylesheetURL: String = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css", pmtilesProtocolURL: String? = "https://unpkg.com/pmtiles@3.2.0/dist/pmtiles.js") {
    self.scriptURL = scriptURL; self.stylesheetURL = stylesheetURL; self.pmtilesProtocolURL = pmtilesProtocolURL
  }
}
public struct MapConfiguration: Hashable, Sendable {
  public var provider: MapProvider
  public var style: MapStyle
  public var assets: MapAssetConfiguration
  public var interactionModes: MapInteractionModes
  public var showsCompass: Bool
  public var showsScale: Bool
  public var attribution: String?
  public init(provider: MapProvider = .openStreetMap, style: MapStyle = .standard, assets: MapAssetConfiguration = .init(), interactionModes: MapInteractionModes = .all, showsCompass: Bool = false, showsScale: Bool = false, attribution: String? = nil) {
    self.provider = provider; self.style = style; self.assets = assets; self.interactionModes = interactionModes; self.showsCompass = showsCompass; self.showsScale = showsScale; self.attribution = attribution
  }
}

public protocol MapContent: View {}
public protocol MapOverlay: MapContent {}
/// Alias retained for source compatibility with SwiftUI map content builders.
public typealias MapContentBuilder = ViewBuilder

public struct Map: View {
  public typealias Body = Never
  private let position: Binding<MapCameraPosition>?
  private let coordinateRegion: Binding<CoordinateRegion>?
  private let selectionWriter: ((String?) -> Void)?
  private let content: AnyView?
  private var configuration: MapConfiguration
  private let cameraFrequency: MapCameraChangeFrequency
  private let cameraChangeAction: ((MapCameraChangeContext) -> Void)?

  public init() { position = nil; coordinateRegion = nil; selectionWriter = nil; content = nil; configuration = .init(); cameraFrequency = .onEnd; cameraChangeAction = nil }
  public init<Inner: View>(@ViewBuilder content: () -> Inner) { position = nil; coordinateRegion = nil; selectionWriter = nil; self.content = AnyView(content()); configuration = .init(); cameraFrequency = .onEnd; cameraChangeAction = nil }
  public init(position: Binding<MapCameraPosition>) { self.init(position: position) { EmptyView() } }
  public init<Inner: View>(position: Binding<MapCameraPosition>, @ViewBuilder content: () -> Inner) { self.position = position; coordinateRegion = nil; selectionWriter = nil; self.content = AnyView(content()); configuration = .init(); cameraFrequency = .onEnd; cameraChangeAction = nil }
  public init<Inner: View>(position: Binding<MapCameraPosition>, interactionModes: MapInteractionModes, @ViewBuilder content: () -> Inner) { self.init(position: position, content: content); configuration.interactionModes = interactionModes }
  public init(coordinateRegion: Binding<CoordinateRegion>) { self.init(coordinateRegion: coordinateRegion) { EmptyView() } }
  public init<Inner: View>(coordinateRegion: Binding<CoordinateRegion>, @ViewBuilder content: () -> Inner) { position = nil; self.coordinateRegion = coordinateRegion; selectionWriter = nil; self.content = AnyView(content()); configuration = .init(); cameraFrequency = .onEnd; cameraChangeAction = nil }
  public init<Inner: View>(coordinateRegion: Binding<CoordinateRegion>, interactionModes: MapInteractionModes, @ViewBuilder content: () -> Inner) { self.init(coordinateRegion: coordinateRegion, content: content); configuration.interactionModes = interactionModes }
  public init<Inner: View, Selection: Hashable>(position: Binding<MapCameraPosition>, selection: Binding<Selection?>, @ViewBuilder content: () -> Inner) {
    self.position = position; coordinateRegion = nil; selectionWriter = Self.makeSelectionWriter(selection); self.content = AnyView(content()); configuration = .init(); cameraFrequency = .onEnd; cameraChangeAction = nil
  }
  public init<Inner: View, Selection: Hashable>(position: Binding<MapCameraPosition>, selection: Binding<Selection?>, interactionModes: MapInteractionModes, @ViewBuilder content: () -> Inner) { self.init(position: position, selection: selection, content: content); configuration.interactionModes = interactionModes }
  public init<Inner: View, Selection: Hashable>(coordinateRegion: Binding<CoordinateRegion>, selection: Binding<Selection?>, @ViewBuilder content: () -> Inner) {
    position = nil; self.coordinateRegion = coordinateRegion; selectionWriter = Self.makeSelectionWriter(selection); self.content = AnyView(content()); configuration = .init(); cameraFrequency = .onEnd; cameraChangeAction = nil
  }
  public init<Inner: View, Selection: Hashable>(coordinateRegion: Binding<CoordinateRegion>, selection: Binding<Selection?>, interactionModes: MapInteractionModes, @ViewBuilder content: () -> Inner) { self.init(coordinateRegion: coordinateRegion, selection: selection, content: content); configuration.interactionModes = interactionModes }
  private static func makeSelectionWriter<S: Hashable>(_ binding: Binding<S?>) -> ((String?) -> Void) {
    { raw in
      guard let raw else { binding.wrappedValue = nil; return }
      if let value = selectionValue(raw, as: S.self) { binding.wrappedValue = value }
    }
  }
  private init(position: Binding<MapCameraPosition>?, coordinateRegion: Binding<CoordinateRegion>?, selectionWriter: ((String?) -> Void)?, content: AnyView?, configuration: MapConfiguration, cameraFrequency: MapCameraChangeFrequency, cameraChangeAction: ((MapCameraChangeContext) -> Void)?) {
    self.position = position; self.coordinateRegion = coordinateRegion; self.selectionWriter = selectionWriter; self.content = content; self.configuration = configuration; self.cameraFrequency = cameraFrequency; self.cameraChangeAction = cameraChangeAction
  }

  public func _render(in context: _RenderContext) -> _RenderNode {
    MapLibreBackend.installIfNeeded()
    let mapID = context.path.map(fiberKeyDescription).joined(separator: "/")
    #if arch(wasm32) && hasFeature(Embedded)
    let node = _RenderNode.element("div"); node.classes = ["mapkit-view", "mapkit-maplibre-host"]
    node.styles = ["position": "relative", "min-height": "240px", "width": "100%", "overflow": "hidden", "border-radius": "12px"]
    let region = position?.wrappedValue.region ?? coordinateRegion.map({ $0.wrappedValue })
    let center = region?.center ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    let spanLat = max(0.01, region?.span.latitudeDelta ?? 0.18)
    let spanLon = max(0.01, region?.span.longitudeDelta ?? 0.18)
    let left = center.longitude - spanLon / 2, right = center.longitude + spanLon / 2
    let bottom = center.latitude - spanLat / 2, top = center.latitude + spanLat / 2
    let frame = _RenderNode.element("iframe")
    frame.attributes["title"] = "OpenStreetMap"
    frame.attributes["loading"] = "lazy"
    frame.attributes["referrerpolicy"] = "strict-origin-when-cross-origin"
    frame.attributes["src"] = "https://www.openstreetmap.org/export/embed.html?bbox=\(left)%2C\(bottom)%2C\(right)%2C\(top)&layer=mapnik&marker=\(center.latitude)%2C\(center.longitude)"
    frame.styles = ["border": "0", "width": "100%", "height": "100%", "min-height": "240px", "display": "block"]
    node.children = [frame]
    node.attributes["data-map-attribution"] = "© OpenStreetMap contributors"
    return node
    #else
    let node = _RenderNode.element("div"); node.classes = ["mapkit-view", "mapkit-maplibre-host"]
    node.styles = ["position": "relative", "min-height": "240px", "width": "100%"]
    node.attributes["role"] = "application"; node.attributes["aria-label"] = "Map"; node.attributes["data-web-mount-key"] = MapLibreBackend.mountKey
    node.attributes["data-map-id"] = mapID; node.attributes["data-map-interaction-modes"] = String(configuration.interactionModes.rawValue); node.attributes["data-map-shows-compass"] = configuration.showsCompass ? "true" : "false"; node.attributes["data-map-shows-scale"] = configuration.showsScale ? "true" : "false"; node.attributes["data-map-camera-frequency"] = cameraFrequency.rawValue; node.attributes["data-map-camera"] = cameraJSON
    if let region = position?.wrappedValue.region ?? coordinateRegion.map({ $0.wrappedValue }) {
      node.attributes["data-map-center"] = "\(region.center.latitude),\(region.center.longitude)"
    }
    let values = configuration.runtimeValues(); node.attributes["data-map-library-url"] = values.libraryURL; node.attributes["data-map-stylesheet-url"] = values.stylesheetURL; node.attributes["data-map-attribution"] = values.attribution
    // Provider credentials are host secrets. Never serialize them into a
    // _RenderNode/DOM attribute or URL; authenticated providers must be wired
    // through a host-owned credential adapter, otherwise the map remains a
    // documented fallback instead of leaking a token.
    if values.accessToken != nil { node.attributes["data-map-authentication"] = "host-managed" }
    if let protocolURL = values.protocolURL {
      node.attributes["data-map-pmtiles-protocol-url"] = protocolURL
    }
    if let styleURL = values.styleURL { node.attributes["data-map-style-url"] = Self.publicMapURL(styleURL) }; if let styleJSON = values.styleJSON { node.attributes["data-map-style-json"] = styleJSON }
    if let content { let child = content._render(in: context.child(_FiberKey("content"))); if !child.isEmpty { node.children = [child] } }
    return node
    #endif
  }
  /// The style URL as the page may show it: no userinfo, and no query item that carries a credential or signature.
  private static func publicMapURL(_ raw: String) -> String {
    guard let question = raw.firstIndex(of: "?") else { return withoutUserinfo(raw) }
    let base = withoutUserinfo(String(raw[..<question]))
    let query = raw[raw.index(after: question)...].split(separator: "&").filter { item in
      // The name as the server reads it: `api%5Fkey` is `api_key`.
      let key = _mapPercentDecodedASCII(item.split(separator: "=", maxSplits: 1).first.map(String.init) ?? "").lowercased()
      return !["key", "apikey", "api_key", "token", "access_token", "secret", "signature"].contains { key == $0 || key.hasSuffix($0) }
    }.joined(separator: "&")
    return query.isEmpty ? base : base + "?" + query
  }
  private var cameraJSON: String {
    if let position { return position.wrappedValue.runtimeJSON }; if let coordinateRegion { return MapCameraPosition.region(coordinateRegion.wrappedValue).runtimeJSON }; return MapCameraPosition.automatic.runtimeJSON
  }
  public func mapStyle(_ value: MapStyle) -> Self { with { $0.style = value } }
  public func mapConfiguration(_ value: MapConfiguration) -> Self { with { $0 = value } }
  public func mapProvider(_ value: MapProvider) -> Self { with { $0.provider = value } }
  public func mapInteractionModes(_ value: MapInteractionModes) -> Self { with { $0.interactionModes = value } }
  public func mapControls(compass: Bool = false, scale: Bool = false) -> Self { with { $0.showsCompass = compass; $0.showsScale = scale } }
  public func onMapCameraChange(frequency: MapCameraChangeFrequency = .onEnd, _ action: @escaping (MapCameraChangeContext) -> Void) -> Self {
    Self(position: position, coordinateRegion: coordinateRegion, selectionWriter: selectionWriter, content: content, configuration: configuration, cameraFrequency: frequency, cameraChangeAction: action)
  }
  private func with(_ update: (inout MapConfiguration) -> Void) -> Self { var value = configuration; update(&value); return Self(position: position, coordinateRegion: coordinateRegion, selectionWriter: selectionWriter, content: content, configuration: value, cameraFrequency: cameraFrequency, cameraChangeAction: cameraChangeAction) }
}

public struct Marker: MapContent {
  public typealias Body = Never
  public let title: String; public let coordinate: CLLocationCoordinate2D; public let systemImage: String?; public let tintColor: Color?; public let selectionID: String?
  public init(_ title: String, coordinate: CLLocationCoordinate2D) { self.title = title; self.coordinate = coordinate; systemImage = nil; tintColor = nil; selectionID = nil }
  public init(_ title: String, systemImage: String, coordinate: CLLocationCoordinate2D) { self.title = title; self.coordinate = coordinate; self.systemImage = systemImage; tintColor = nil; selectionID = nil }
  private init(title: String, coordinate: CLLocationCoordinate2D, systemImage: String?, tintColor: Color?, selectionID: String?) { self.title = title; self.coordinate = coordinate; self.systemImage = systemImage; self.tintColor = tintColor; self.selectionID = selectionID }
  public func tint(_ color: Color) -> Self { Self(title: title, coordinate: coordinate, systemImage: systemImage, tintColor: color, selectionID: selectionID) }
  public func mapTag<Tag: Hashable>(_ value: Tag) -> Self { Self(title: title, coordinate: coordinate, systemImage: systemImage, tintColor: tintColor, selectionID: fiberKeyDescription(_FiberKey(value))) }
  public func _render(in context: _RenderContext) -> _RenderNode { let node = _RenderNode.element("div"); node.classes = ["mapkit-feature", "mapkit-marker"]; node.attributes["data-map-feature"] = "marker"; node.attributes["data-map-title"] = title; node.attributes["data-map-latitude"] = String(coordinate.latitude); node.attributes["data-map-longitude"] = String(coordinate.longitude); if let systemImage { node.attributes["data-map-system-image"] = systemImage }; if let tintColor { node.attributes["data-map-tint"] = tintColor.cssValue }; if let selectionID { node.attributes["data-map-selection"] = selectionID }; node.children = [Text(title)._render(in: context.child(_FiberKey("label")))]; return node }
}

public struct Annotation<Label: View>: MapContent {
  public typealias Body = Never
  public let title: String; public let coordinate: CLLocationCoordinate2D; public let anchor: UnitPoint; public let label: Label; public let selectionID: String?
  public init(_ title: String, coordinate: CLLocationCoordinate2D, anchor: UnitPoint = .center, @ViewBuilder content: () -> Label) { self.title = title; self.coordinate = coordinate; self.anchor = anchor; label = content(); selectionID = nil }
  private init(title: String, coordinate: CLLocationCoordinate2D, anchor: UnitPoint, label: Label, selectionID: String?) { self.title = title; self.coordinate = coordinate; self.anchor = anchor; self.label = label; self.selectionID = selectionID }
  public func mapTag<Tag: Hashable>(_ value: Tag) -> Self { Self(title: title, coordinate: coordinate, anchor: anchor, label: label, selectionID: fiberKeyDescription(_FiberKey(value))) }
  public func _render(in context: _RenderContext) -> _RenderNode { let node = _RenderNode.element("div"); node.classes = ["mapkit-feature", "mapkit-annotation"]; node.attributes["data-map-feature"] = "annotation"; node.attributes["data-map-title"] = title; node.attributes["data-map-latitude"] = String(coordinate.latitude); node.attributes["data-map-longitude"] = String(coordinate.longitude); node.attributes["data-map-anchor"] = "\(anchor.x),\(anchor.y)"; if let selectionID { node.attributes["data-map-selection"] = selectionID }; node.children = [label._render(in: context.child(_FiberKey("label")))]; return node }
}

public struct MapPolyline: MapOverlay {
  public typealias Body = Never
  public let coordinates: [CLLocationCoordinate2D]; public let strokeColor: Color; public let lineWidth: Double
  public init(_ coordinates: [CLLocationCoordinate2D]) { self.coordinates = coordinates; strokeColor = .blue; lineWidth = 3 }
  private init(coordinates: [CLLocationCoordinate2D], strokeColor: Color, lineWidth: Double) { self.coordinates = coordinates; self.strokeColor = strokeColor; self.lineWidth = lineWidth }
  public func stroke(_ color: Color, lineWidth: Double = 3) -> Self { Self(coordinates: coordinates, strokeColor: color, lineWidth: lineWidth) }
  public func _render(in context: _RenderContext) -> _RenderNode { let node = _RenderNode.element("div"); node.classes = ["mapkit-feature", "mapkit-polyline"]; node.attributes["data-map-feature"] = "polyline"; node.attributes["data-map-coordinates"] = coordinates.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ";"); node.attributes["data-map-stroke"] = strokeColor.cssValue; node.attributes["data-map-line-width"] = String(lineWidth); return node }
}

public struct MapPolygon: MapOverlay {
  public typealias Body = Never
  public let coordinates: [CLLocationCoordinate2D]; public let fillColor: Color; public let strokeColor: Color; public let lineWidth: Double
  public init(_ coordinates: [CLLocationCoordinate2D]) { self.coordinates = coordinates; fillColor = .blue.opacity(0.25); strokeColor = .blue; lineWidth = 2 }
  private init(coordinates: [CLLocationCoordinate2D], fillColor: Color, strokeColor: Color, lineWidth: Double) { self.coordinates = coordinates; self.fillColor = fillColor; self.strokeColor = strokeColor; self.lineWidth = lineWidth }
  public func fill(_ color: Color) -> Self { Self(coordinates: coordinates, fillColor: color, strokeColor: strokeColor, lineWidth: lineWidth) }
  public func stroke(_ color: Color, lineWidth: Double = 2) -> Self { Self(coordinates: coordinates, fillColor: fillColor, strokeColor: color, lineWidth: lineWidth) }
  public func _render(in context: _RenderContext) -> _RenderNode { let node = _RenderNode.element("div"); node.classes = ["mapkit-feature", "mapkit-polygon"]; node.attributes["data-map-feature"] = "polygon"; node.attributes["data-map-coordinates"] = coordinates.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ";"); node.attributes["data-map-fill"] = fillColor.cssValue; node.attributes["data-map-stroke"] = strokeColor.cssValue; node.attributes["data-map-line-width"] = String(lineWidth); return node }
}

public struct MapCircle: MapOverlay {
  public typealias Body = Never
  public let center: CLLocationCoordinate2D; public let radius: Double; public var fillColor: Color; public var strokeColor: Color
  public init(center: CLLocationCoordinate2D, radius: Double) { self.center = center; self.radius = radius; fillColor = .blue.opacity(0.2); strokeColor = .blue }
  public func fill(_ color: Color) -> Self { var copy = self; copy.fillColor = color; return copy }
  public func stroke(_ color: Color) -> Self { var copy = self; copy.strokeColor = color; return copy }
  public func _render(in context: _RenderContext) -> _RenderNode { let node = _RenderNode.element("div"); node.classes = ["mapkit-feature", "mapkit-circle"]; node.attributes["data-map-feature"] = "circle"; node.attributes["data-map-latitude"] = String(center.latitude); node.attributes["data-map-longitude"] = String(center.longitude); node.attributes["data-map-radius"] = String(radius); node.attributes["data-map-fill"] = fillColor.cssValue; node.attributes["data-map-stroke"] = strokeColor.cssValue; return node }
}

/// A number as JSON: a NaN or infinite value has no JSON form, so it is written as `null`.
private func jsonNumber(_ value: Double) -> String {
  value.isFinite ? String(value) : "null"
}

private extension MapCameraPosition {
  var runtimeJSON: String {
    switch self {
    case .automatic: return "{\"kind\":\"automatic\"}"
    case .userLocation: return "{\"kind\":\"userLocation\"}"
    case .region(let r): return "{\"kind\":\"region\",\"latitude\":\(jsonNumber(r.center.latitude)),\"longitude\":\(jsonNumber(r.center.longitude)),\"latitudeDelta\":\(jsonNumber(r.span.latitudeDelta)),\"longitudeDelta\":\(jsonNumber(r.span.longitudeDelta)),\"zoom\":10}"
    case .camera(let c): return "{\"kind\":\"camera\",\"latitude\":\(jsonNumber(c.centerCoordinate.latitude)),\"longitude\":\(jsonNumber(c.centerCoordinate.longitude)),\"distance\":\(jsonNumber(c.distance)),\"heading\":\(jsonNumber(c.heading)),\"pitch\":\(jsonNumber(c.pitch)),\"zoom\":\(jsonNumber(c.zoom ?? 8))}"
    }
  }
}

private extension MapConfiguration {
  struct RuntimeValues { let libraryURL: String; let stylesheetURL: String; let styleURL: String?; let styleJSON: String?; let attribution: String; let protocolURL: String?; let accessToken: String? }
  func runtimeValues() -> RuntimeValues {
    let p: MapProviderConfiguration; let json: String?
    switch provider {
    case .openStreetMap:
      p = MapProviderConfiguration(tileURLTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png", attribution: "© OpenStreetMap contributors"); json = Self.osmStyleJSON(tiles: p.tileURLTemplate!, attribution: p.attribution)
    case .pmtilesSource(let url, let attribution): p = MapProviderConfiguration(tileURLTemplate: url, attribution: attribution, protocolURL: assets.pmtilesProtocolURL); json = Self.pmtilesStyleJSON(url: url, attribution: attribution)
    case .mapTilerSource(let style, let key): p = MapProviderConfiguration(styleURL: "https://api.maptiler.com/maps/\(style)/style.json?key=\(percentEncoded(key))", attribution: "© MapTiler © OpenStreetMap contributors", accessToken: key); json = nil
    case .stadiaMapsSource(let style, let key): p = MapProviderConfiguration(styleURL: "https://tiles.stadiamaps.com/styles/\(style).json\(key.map { "?api_key=\(percentEncoded($0))" } ?? "")", attribution: "© Stadia Maps © OpenStreetMap contributors", accessToken: key); json = nil
    case .custom(let value): p = value; json = value.tileURLTemplate.map { Self.osmStyleJSON(tiles: $0, attribution: value.attribution) }
    }
    switch style {
    case .custom(let url): return RuntimeValues(libraryURL: assets.scriptURL, stylesheetURL: assets.stylesheetURL, styleURL: url, styleJSON: nil, attribution: htmlEscaped(attribution ?? p.attribution), protocolURL: p.protocolURL, accessToken: p.accessToken)
    default: return RuntimeValues(libraryURL: assets.scriptURL, stylesheetURL: assets.stylesheetURL, styleURL: p.styleURL, styleJSON: json, attribution: htmlEscaped(attribution ?? p.attribution), protocolURL: p.protocolURL, accessToken: p.accessToken)
    }
  }
  static func osmStyleJSON(tiles: String, attribution: String) -> String { "{\"version\":8,\"sources\":{\"osm\":{\"type\":\"raster\",\"tiles\":[\"\(jsonEscape(tiles))\"],\"tileSize\":256,\"attribution\":\"\(jsonEscape(htmlEscaped(attribution)))\"}},\"layers\":[{\"id\":\"osm\",\"type\":\"raster\",\"source\":\"osm\"}]}" }
  static func pmtilesStyleJSON(url: String, attribution: String) -> String { "{\"version\":8,\"sources\":{\"pmtiles\":{\"type\":\"raster\",\"url\":\"pmtiles://\(jsonEscape(url))\",\"tileSize\":256,\"attribution\":\"\(jsonEscape(htmlEscaped(attribution)))\"}},\"layers\":[{\"id\":\"pmtiles\",\"type\":\"raster\",\"source\":\"pmtiles\"}]}" }
}
/// `url` without its userinfo (`user:pass@`). The authority ends at the first "/" (the query is already removed).
private func withoutUserinfo(_ raw: String) -> String {
  // Read as the browser's URL parser reads an http(s) address: leading spaces and controls and every tab or line break
  // are dropped, and after the scheme any run of "/" or "\\" opens the authority, which ends at "/", "\\", "?" or "#".
  // So "https:user:pass@host", "https:\\\\user@host" and "https://user@host" all lose their credentials.
  var scalars: [Unicode.Scalar] = []
  for scalar in raw.unicodeScalars {
    if scalars.isEmpty && scalar.value <= 0x20 { continue }
    if scalar == "\t" || scalar == "\n" || scalar == "\r" { continue }
    scalars.append(scalar)
  }
  guard let colon = scalars.firstIndex(of: ":") else { return raw }
  var start = colon + 1
  while start < scalars.count, scalars[start] == "/" || scalars[start] == "\\" { start += 1 }
  var end = start
  while end < scalars.count, !["/", "\\", "?", "#"].contains(scalars[end]) { end += 1 }
  guard let at = scalars[start ..< end].lastIndex(of: "@") else { return raw }
  var result = String.UnicodeScalarView()
  result.append(contentsOf: scalars[..<colon])
  result.append(contentsOf: "://".unicodeScalars)
  result.append(contentsOf: scalars[(at + 1)...])
  return String(result)
}

/// `%XX` escapes of ASCII decoded (a query name is compared as the server decodes it); other bytes stay as written.
private func _mapPercentDecodedASCII(_ text: String) -> String {
  let bytes = Array(text.utf8)
  var output: [UInt8] = []
  var index = 0
  func hex(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 0x30...0x39: return byte - 0x30
    case 0x41...0x46: return byte - 0x37
    case 0x61...0x66: return byte - 0x57
    default: return nil
    }
  }
  while index < bytes.count {
    if bytes[index] == 0x25, index + 2 < bytes.count, let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]), high < 8 {
      output.append(high << 4 | low)
      index += 3
    } else {
      output.append(bytes[index])
      index += 1
    }
  }
  return String(decoding: output, as: UTF8.self)
}

/// `value` with the characters that `innerHTML` reads as markup escaped.
private func htmlEscaped(_ value: String) -> String {
  var escaped = ""
  for scalar in value.unicodeScalars {
    switch scalar {
    case "&": escaped += "&amp;"
    case "<": escaped += "&lt;"
    case ">": escaped += "&gt;"
    case "\"": escaped += "&quot;"
    case "'": escaped += "&#39;"
    default: escaped.unicodeScalars.append(scalar)
    }
  }
  return escaped
}

/// `value` percent-encoded for a URL query (RFC 3986 unreserved characters are kept).
private func percentEncoded(_ value: String) -> String {
  let hex = Array("0123456789ABCDEF")
  var encoded = ""
  for byte in value.utf8 {
    let unreserved = (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 45 || byte == 46 || byte == 95 || byte == 126
    if unreserved {
      encoded.unicodeScalars.append(Unicode.Scalar(byte))
    } else {
      encoded += "%" + String(hex[Int(byte >> 4)]) + String(hex[Int(byte & 15)])
    }
  }
  return encoded
}

private func jsonEscape(_ value: String) -> String {
  // `String.replacingOccurrences` is a Foundation API and is unavailable in
  // Embedded Swift. JSON escaping here only needs the characters that can
  // alter the generated style document, so keep the implementation in the
  // Swift standard library.
  // Per Unicode scalar, not per Character: a quote or backslash followed by a combining mark is one Character that
  // matches no case, and would close the string. Control characters are written as \u00XX.
  var escaped = ""
  escaped.reserveCapacity(value.utf8.count)
  for scalar in value.unicodeScalars {
    switch scalar {
    case "\\": escaped += "\\\\"
    case "\"": escaped += "\\\""
    case "\n": escaped += "\\n"
    case "\r": escaped += "\\r"
    case "\t": escaped += "\\t"
    default:
      if scalar.value < 0x20 {
        let digits = Array("0123456789abcdef")
        escaped += "\\u00" + String(digits[Int(scalar.value >> 4)]) + String(digits[Int(scalar.value & 15)])
      } else {
        escaped.unicodeScalars.append(scalar)
      }
    }
  }
  return escaped
}

private func selectionValue<S: Hashable>(_ raw: String, as type: S.Type) -> S? {
  if type == String.self { return raw as? S }
  if type == Int.self { return Int(raw) as? S }
  if type == UInt.self { return UInt(raw) as? S }
  if type == Int64.self { return Int64(raw) as? S }
  if type == UInt64.self { return UInt64(raw) as? S }
  if type == Double.self { return Double(raw) as? S }
  if type == Bool.self {
    switch raw.lowercased() {
    case "true", "1", "yes": return true as? S
    case "false", "0", "no": return false as? S
    default: return nil
    }
  }
  #if !hasFeature(Embedded)
  return raw as? S
  #else
  return nil
  #endif
}
