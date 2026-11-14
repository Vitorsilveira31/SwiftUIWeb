// SwiftUI coordinate spaces. Names are carried as compact render metadata
// (`data-coordinate-space`); the browser host reports the frames of the
// ancestor spaces it sees and GeometryMeasurement.swift resolves them.

/// A resolved coordinate space: SwiftUI's `CoordinateSpace`.
///
/// SwiftUI names spaces with `AnyHashable`. Embedded Swift has no
/// `AnyHashable`, so names are stored as a string key: `String` names are used
/// verbatim and other `Hashable` names are keyed by their hash value.
public enum CoordinateSpace: Hashable, Sendable {
  case local, global, named(String)

  /// A named space keyed by an arbitrary `Hashable` value, for example an
  /// application enum. The same value always resolves to the same space.
  public static func named<Name: Hashable>(_ name: Name) -> CoordinateSpace {
    .named(_coordinateSpaceKey(name))
  }

  public var isGlobal: Bool { self == .global }
  public var isLocal: Bool { self == .local }

  var _geometrySpace: _GeometrySpace {
    switch self {
    case .local: return .local
    case .global: return .global
    case .named(let key): return _GeometrySpaceKeys.space(forNamedKey: key)
    }
  }
}

/// SwiftUI's protocol for the typed coordinate-space spellings
/// (`.local`, `.global`, `.named(_:)`, `.scrollView`).
public protocol CoordinateSpaceProtocol {
  var coordinateSpace: CoordinateSpace { get }
}

public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Hashable, Sendable {
  public let coordinateSpace: CoordinateSpace
  package init(key: String) { coordinateSpace = .named(key) }

  var _key: String {
    if case .named(let key) = coordinateSpace { return key }
    return ""
  }
}

public struct LocalCoordinateSpace: CoordinateSpaceProtocol, Hashable, Sendable {
  public init() {}
  public var coordinateSpace: CoordinateSpace { .local }
}

public struct GlobalCoordinateSpace: CoordinateSpaceProtocol, Hashable, Sendable {
  public init() {}
  public var coordinateSpace: CoordinateSpace { .global }
}

public extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
  static func named(_ name: some Hashable) -> NamedCoordinateSpace {
    NamedCoordinateSpace(key: _coordinateSpaceKey(name))
  }

}

public extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {
  static var local: LocalCoordinateSpace { LocalCoordinateSpace() }
}

public extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {
  static var global: GlobalCoordinateSpace { GlobalCoordinateSpace() }
}

/// String names are used verbatim, minus the host payload separators.
func _coordinateSpaceKey(_ name: String) -> String {
  guard name.unicodeScalars.contains(where: { $0 == "\u{1E}" || $0 == "\u{1F}" }) else { return name }
  var scalars = String.UnicodeScalarView()
  for scalar in name.unicodeScalars where scalar != "\u{1E}" && scalar != "\u{1F}" { scalars.append(scalar) }
  return String(scalars)
}

/// Every generic spelling of a name (`.named(_:)`, `coordinateSpace(name:)`)
/// goes through this function, so a producer and its consumers always agree on
/// the key. String names are recognized with a concrete cast, which Embedded
/// Swift supports for specialized generics (as `_swiftUIWebDescribe` relies on),
/// so they stay readable in the DOM in both builds. Other names have no
/// reflection in Embedded Swift and are keyed by their hash value, which
/// identifies the space consistently within the running application.
func _coordinateSpaceKey<Name: Hashable>(_ name: Name) -> String {
  if let string = name as? String { return _coordinateSpaceKey(string) }
  return "swiftuiweb.hash:\(_distinctIDNumber(name))"
}

/// Registers a SwiftUI named coordinate space for the modified view. The key
/// is emitted as render metadata; the browser host reports the frame of the
/// nearest matching ancestor with every geometry measurement.
nonisolated struct CoordinateSpaceModifier: ViewModifier {
  let name: String
  init(key: String) { name = key }

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // Reserved scroll-view spaces are provided by ScrollView itself.
    guard case .named = _GeometrySpaceKeys.space(forNamedKey: name) else { return }
    // A fragment (Group, ForEach, TupleView) has no DOM host. As in SwiftUI,
    // the modifier then applies to each child view.
    if case .fragment = node.kind {
      for child in node.children { _apply(to: child, context: &context) }
      return
    }
    node.attributes["data-coordinate-space"] = name
  }
}

public extension View {
  /// Names the modified view's coordinate space (SwiftUI iOS 17+ spelling).
  nonisolated func coordinateSpace(_ name: NamedCoordinateSpace) -> some View {
    modifier(CoordinateSpaceModifier(key: name._key))
  }

  /// Names the modified view's coordinate space with any `Hashable` value.
  nonisolated func coordinateSpace<Name: Hashable>(name: Name) -> some View {
    modifier(CoordinateSpaceModifier(key: _coordinateSpaceKey(name)))
  }
}
