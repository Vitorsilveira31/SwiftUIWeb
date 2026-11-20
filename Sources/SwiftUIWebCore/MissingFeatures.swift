// SwiftUI-shaped capabilities implemented in the backend-neutral core. Most
// values carry semantic metadata; Canvas additionally records a compact
// drawing command IR that browser and future native hosts can replay.

@_spi(Renderer) import SwiftUIWebTransferable
/// Embedded/WASI uses the same lightweight `CGSize` value exposed by the
/// compatibility layer, keeping Canvas closures source-compatible with code
/// that spells the parameter as `CGSize`.
package typealias SwiftUIWebCanvasSize = CGSize

// MARK: - Button styles and control environment

/// The CSS token the browser host uses for a built-in button style. Built-in
/// styles report it through `_swiftUIWebButtonStyleToken`; it is not public API.
package struct ButtonStyleValue: Hashable, Sendable {
  package let rawValue: String
  package init(_ rawValue: String) { self.rawValue = rawValue }
  package static let automatic = ButtonStyleValue("automatic")
  package static let plain = ButtonStyleValue("plain")
  package static let bordered = ButtonStyleValue("bordered")
  package static let borderedProminent = ButtonStyleValue("bordered-prominent")
  package static let borderless = ButtonStyleValue("borderless")
  package static let link = ButtonStyleValue("link")
}

public struct ButtonStyleConfiguration {
  @MainActor @preconcurrency public struct Label: View {
    public typealias Body = Never
    package let body: AnyView
    package init(body: AnyView) { self.body = body }
    public func _render(in context: _RenderContext) -> _RenderNode { body._render(in: context) }
  }
  public let role: ButtonRole?
  public let label: Label
  public let isPressed: Bool
  package let _action: () -> Void
  package init(role: ButtonRole?, label: Label, isPressed: Bool = false) {
    self.role = role; self.label = label; self.isPressed = isPressed; self._action = {}
  }
  package init(role: ButtonRole?, label: Label, isPressed: Bool, action: @escaping () -> Void) {
    self.role = role; self.label = label; self.isPressed = isPressed; self._action = action
  }
}

@MainActor @preconcurrency
public protocol ButtonStyle {
  associatedtype Body: View
  typealias Configuration = ButtonStyleConfiguration
  @MainActor @preconcurrency @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
  /// The browser token for a built-in style; `nil` for app-defined styles,
  /// whose `makeBody` the runtime always calls. Underscored: not SwiftUI API.
  nonisolated var _swiftUIWebButtonStyleToken: String? { get }
}

public extension ButtonStyle {
  nonisolated var _swiftUIWebButtonStyleToken: String? { nil }
}

/// PrimitiveButtonStyle is kept separate, matching SwiftUI's API. The web
/// runtime currently realizes both protocols through the same semantic button
/// element, but custom primitive styles still compile and receive a trigger.
public struct PrimitiveButtonStyleConfiguration {
  @MainActor @preconcurrency public struct Label: View {
    public typealias Body = Never
    package let body: AnyView
    package init(body: AnyView) { self.body = body }
    public func _render(in context: _RenderContext) -> _RenderNode { body._render(in: context) }
  }
  public let role: ButtonRole?
  public let label: Label
  private let action: () -> Void
  package init(role: ButtonRole?, label: Label, action: @escaping () -> Void) {
    self.role = role; self.label = label; self.action = action
  }
  public func trigger() { action() }
}

@MainActor @preconcurrency
public protocol PrimitiveButtonStyle {
  associatedtype Body: View
  typealias Configuration = PrimitiveButtonStyleConfiguration
  @MainActor @preconcurrency @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
  /// See `ButtonStyle._swiftUIWebButtonStyleToken`.
  nonisolated var _swiftUIWebButtonStyleToken: String? { get }
}

public extension PrimitiveButtonStyle {
  nonisolated var _swiftUIWebButtonStyleToken: String? { nil }
}

// Apple's built-in button styles all conform to PrimitiveButtonStyle, and
// their static members are declared on that protocol (see below).

public nonisolated struct DefaultButtonStyle: PrimitiveButtonStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: DefaultButtonStyle.Configuration) -> some View { configuration.label }
  public nonisolated var _swiftUIWebButtonStyleToken: String? { "automatic" }
}

public nonisolated struct PlainButtonStyle: PrimitiveButtonStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: PlainButtonStyle.Configuration) -> some View { configuration.label }
  public nonisolated var _swiftUIWebButtonStyleToken: String? { "plain" }
}

public nonisolated struct LinkButtonStyle: PrimitiveButtonStyle {
  public nonisolated init() {}
  public nonisolated func makeBody(configuration: LinkButtonStyle.Configuration) -> some View { configuration.label }
  public nonisolated var _swiftUIWebButtonStyleToken: String? { "link" }
}

public extension PrimitiveButtonStyle where Self == DefaultButtonStyle {
  static nonisolated var automatic: DefaultButtonStyle { DefaultButtonStyle() }
}

public extension PrimitiveButtonStyle where Self == PlainButtonStyle {
  @MainActor @preconcurrency static var plain: PlainButtonStyle { PlainButtonStyle() }
}

public extension PrimitiveButtonStyle where Self == LinkButtonStyle {
  @MainActor @preconcurrency static var link: LinkButtonStyle { LinkButtonStyle() }
}

public enum ControlSize: Hashable, Sendable {
  case mini, small, regular, large, extraLarge

  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  package var rawValue: String {
    switch self {
    case .mini: "mini"
    case .small: "small"
    case .regular: "regular"
    case .large: "large"
    case .extraLarge: "extraLarge"
    }
  }
}

package nonisolated struct TintModifier: ViewModifier {
  package let color: Color?
  package init(color: Color?) { self.color = color }
  /// `.tint(.accentColor)` names the app's own accent: the catalog's `AccentColor` (the app tint), or the theme's primary
  /// without one.
  private var isAppAccent: Bool { color?.cssValue == Color.accentColor.cssValue }
  private static let appAccentCSS = "var(--asset-color-AccentColor, var(--color-swu-primary))"
  @MainActor package func _modifyContext(_ context: inout _RenderContext) { context.environment.tint = isAppAccent ? nil : color }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if isAppAccent {
      node.attributes["data-tint"] = Self.appAccentCSS
      node.styles["--tint-color"] = Self.appAccentCSS
    } else if let color {
      node.attributes["data-tint"] = color.cssValue
      node.styles["--tint-color"] = color.cssValue
    }
  }
}

public extension View {
  @_disfavoredOverload nonisolated func tint(_ color: Color?) -> some View {
    // Optional tints match SwiftUI's ability to clear an inherited tint.  The
    // nil case is represented by a no-op modifier so the source remains
    // portable without adding a second overload.
    modifier(TintModifier(color: color))
  }
}

// MARK: - Responsive composition

// MARK: - ScrollViewReader

public struct UnitPoint: Hashable, Sendable {
  public let x: Double
  public let y: Double
  public init(x: Double, y: Double) { self.x = x; self.y = y }
  public static let zero = UnitPoint(x: 0, y: 0)
  public static let top = UnitPoint(x: 0.5, y: 0)
  public static let center = UnitPoint(x: 0.5, y: 0.5)
  public static let bottom = UnitPoint(x: 0.5, y: 1)
  public static let leading = UnitPoint(x: 0, y: 0.5)
  public static let trailing = UnitPoint(x: 1, y: 0.5)
  public static let topLeading = UnitPoint(x: 0, y: 0)
  public static let topTrailing = UnitPoint(x: 1, y: 0)
  public static let bottomLeading = UnitPoint(x: 0, y: 1)
  public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

/// SwiftUI's scroll position value. It names a view ID, an edge, a point, or a
/// single axis of a point; `View.scrollPosition(_:anchor:)` keeps it in sync
/// with the rendered scroll container. As in SwiftUI, a user scroll replaces
/// the target with `isPositionedByUser == true` and no target.
public struct ScrollPosition: @unchecked Sendable {
  // The renderer's bookkeeping. `anchor` is the unit point used when an ID
  // target is scrolled into view.
  package var anchor: UnitPoint?
#if hasFeature(Embedded)
  package var storedID: String?
#else
  package var storedID: (any Hashable & Sendable)?
#endif
  package var storedEdge: Edge?
  // `point` names both axes; `scrollTo(x:)` and `scrollTo(y:)` name one.
  package var storedPoint: CGPoint?
  package var storedX: CGFloat?
  package var storedY: CGFloat?
  // Each `scrollTo` is a new request, so two requests for the same target
  // compare unequal (as they do in SwiftUI). Initializers do not count.
  package var storedRequest: UInt = 0
  public var isPositionedByUser: Bool = false

  public init(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
    self.init(idType: Never.self)
    _setID(id)
    self.anchor = anchor
  }

  public init(idType: (some Hashable & Sendable).Type = Never.self) {}

  public init(idType: (some Hashable & Sendable).Type = Never.self, edge: Edge) {
    self.init(idType: idType)
    _setEdge(edge)
  }

  public init(idType: (some Hashable & Sendable).Type = Never.self, point: CGPoint) {
    self.init(idType: idType)
    _setPoint(point)
  }

  public init(idType: (some Hashable & Sendable).Type = Never.self, x: CGFloat, y: CGFloat) {
    self.init(idType: idType)
    _setPoint(CGPoint(x: x, y: y))
  }

  public init(idType: (some Hashable & Sendable).Type = Never.self, x: CGFloat) {
    self.init(idType: idType)
    _setAxes(x: x, y: nil)
  }

  public init(idType: (some Hashable & Sendable).Type = Never.self, y: CGFloat) {
    self.init(idType: idType)
    _setAxes(x: nil, y: y)
  }

  public mutating func scrollTo(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
    _setID(id)
    if let anchor { self.anchor = anchor }
    storedRequest &+= 1
  }

  public mutating func scrollTo(edge: Edge) {
    _setEdge(edge)
    storedRequest &+= 1
  }

  public mutating func scrollTo(point: CGPoint) {
    _setPoint(point)
    storedRequest &+= 1
  }

  public mutating func scrollTo(x: CGFloat, y: CGFloat) {
    _setPoint(CGPoint(x: x, y: y))
    storedRequest &+= 1
  }

  public mutating func scrollTo(x: CGFloat) {
    _setAxes(x: x, y: nil)
    storedRequest &+= 1
  }

  public mutating func scrollTo(y: CGFloat) {
    _setAxes(x: nil, y: y)
    storedRequest &+= 1
  }

  public var edge: Edge? { storedEdge }
  public var point: CGPoint? { storedPoint }
  public var x: CGFloat? { storedX }
  public var y: CGFloat? { storedY }

  public var viewID: (any Hashable & Sendable)? { storedID }

  public static func == (lhs: ScrollPosition, rhs: ScrollPosition) -> Bool {
    guard lhs.anchor == rhs.anchor, lhs.storedEdge == rhs.storedEdge,
          lhs.storedPoint == rhs.storedPoint, lhs.storedX == rhs.storedX, lhs.storedY == rhs.storedY,
          lhs.storedRequest == rhs.storedRequest, lhs.isPositionedByUser == rhs.isPositionedByUser
    else { return false }
#if hasFeature(Embedded)
    return lhs.storedID == rhs.storedID
#else
    return lhs.storedID.map { AnyHashable($0) } == rhs.storedID.map { AnyHashable($0) }
#endif
  }

  public func viewID<T: Hashable & Sendable>(type: T.Type) -> T? {
    storedID as? T
  }

  /// Clears the target and records the scroll the user made, as SwiftUI does.
  package mutating func _setPositionedByUser() {
    _clearTarget()
    isPositionedByUser = true
  }

  private mutating func _clearTarget() {
    storedID = nil
    storedEdge = nil
    storedPoint = nil
    storedX = nil
    storedY = nil
    isPositionedByUser = false
  }

  private mutating func _setID<ID: Hashable & Sendable>(_ id: ID) {
    _clearTarget()
#if hasFeature(Embedded)
    storedID = fiberKeyDescription(_FiberKey(id))
#else
    storedID = id
#endif
  }

  private mutating func _setEdge(_ edge: Edge) {
    _clearTarget()
    storedEdge = edge
    switch edge {
    case .top: anchor = .top
    case .bottom: anchor = .bottom
    case .leading: anchor = .leading
    case .trailing: anchor = .trailing
    }
  }

  private mutating func _setPoint(_ point: CGPoint) {
    _clearTarget()
    storedPoint = point
  }

  private mutating func _setAxes(x: CGFloat?, y: CGFloat?) {
    _clearTarget()
    storedX = x
    storedY = y
  }

  @_spi(Renderer) public var _idDescription: String? {
#if hasFeature(Embedded)
    storedID
#else
    storedID.map { fiberKeyDescription(_FiberKey($0)) }
#endif
  }
}

extension ScrollPosition: Equatable {}

/// Host-neutral scroll request bridge.  BrowserApp installs the DOM handler;
/// static/WASI hosts may observe the last request or provide their own hook.
@MainActor package enum ScrollViewRuntime {
  package static var handler: ((String, UnitPoint?) -> Void)?
  package static private(set) var lastRequest: (String, UnitPoint?)?
  package static private(set) var lastScope: String?
  package static func install(_ handler: ((String, UnitPoint?) -> Void)?) { self.handler = handler }
  static func request(id: String, anchor: UnitPoint?, scope: String? = nil) {
    lastRequest = (id, anchor)
    lastScope = scope
    handler?(id, anchor)
  }
  package static func _consumeLastRequest() -> (String, UnitPoint?)? {
    let request = lastRequest
    lastRequest = nil
    return request
  }
  package static func _consumeLastScope() -> String? {
    let scope = lastScope
    lastScope = nil
    return scope
  }
}

public struct ScrollViewProxy {
  fileprivate let scope: String?
  fileprivate init(scope: String?) { self.scope = scope }
 public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
    let key = fiberKeyDescription(_FiberKey(id))
    let scope = self.scope
    _assumeMainActor { ScrollViewRuntime.request(id: key, anchor: anchor, scope: scope) }
  }
}

public nonisolated struct ScrollViewReader<Content: View>: View {
  public typealias Body = Never
  public let content: (ScrollViewProxy) -> Content
  public nonisolated init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) { self.content = content }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["scroll-view-reader"]
    node.attributes["data-scroll-view-reader"] = "true"
    let scope = context._compactPathID + "/reader"
    node.attributes["data-scroll-reader-id"] = scope
    let child = content(ScrollViewProxy(scope: scope))._render(in: context.child(_FiberKey("content")))
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

// MARK: - Refresh, redaction and safe-area composition

public struct RefreshAction: Sendable {
  private let action: @MainActor () async -> Void
  package init(_ action: @escaping @MainActor () async -> Void) { self.action = action }
 public func callAsFunction() async { await action() }
}

public struct RedactionReasons: OptionSet, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let placeholder = RedactionReasons(rawValue: 1 << 0)
  public static let privacy = RedactionReasons(rawValue: 1 << 1)
  package static let text = RedactionReasons(rawValue: 1 << 2)
  package static let all: RedactionReasons = [.placeholder, .privacy, .text]
}

// MARK: - ShareLink

/// Platform-neutral sharing hook.  The browser adapter installs a
/// `navigator.share` implementation when available; static/WASI hosts retain
/// the semantic metadata and may provide their own handler.
package enum ShareRuntime {
  @MainActor package static var handler: ((String, String?, String?) -> Void)?
  @MainActor package static func install(_ handler: ((String, String?, String?) -> Void)?) { self.handler = handler }
  @MainActor fileprivate static func share(item: String, subject: String?, message: String?) {
    handler?(item, subject, message)
  }
}

/// A SwiftUI-shaped share control.  `Item` remains generic at the call site,
/// while the host receives a compact string payload that works for String,
/// URL, and other common shareable values without exposing browser types.
public nonisolated struct ShareLink<Label: View>: View {
  public typealias Body = Never
  private let item: String?
  private let subject: String?
  private let message: String?
  private let label: Label

  /// Apple's `ShareLink` takes a `String` or `URL` item (any other `Transferable` also needs a `preview:`, which
  /// `ApplePlatformParity.swift` declares). Both are described to the host as the same string payload.
  public nonisolated init(item: String, subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) {
    self.init(described: item, subject: subject, message: message, label: label())
  }

  public nonisolated init(item: URL, subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) {
    self.init(described: _swiftUIWebDescribe(item), subject: subject, message: message, label: label())
  }

  /// The one designated initializer: every public spelling describes its item and resolves its texts here.
  package init(described item: String?, subject: Text?, message: Text?, label: Label) {
    self.item = item
    self.subject = subject?.value
    self.message = message?.value
    self.label = label
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("button")
    let styleClass = context.environment.buttonStyleIsCustom
      ? "button-custom"
      : "button-" + context.environment.buttonStyle.rawValue
    node.classes = [
      "share-link",
      "push-button",
      styleClass,
      "control-\(context.environment.controlSize.rawValue)"
    ]
    node.attributes["data-control-kind"] = "share-link"
    node.attributes["data-button-style"] = context.environment.buttonStyle.rawValue
    node.attributes["data-control-size"] = context.environment.controlSize.rawValue
    if context.environment.buttonStyleIsCustom { node.attributes["data-button-style-custom"] = "true" }
    if let tint = context.environment.tint {
      node.attributes["data-tint"] = tint.cssValue
      node.styles["--tint-color"] = tint.cssValue
    }
    node.attributes["type"] = "button"
    node.attributes["aria-label"] = "Share"
    if let item { node.attributes["data-share-item"] = item }
    if let subject { node.attributes["data-share-subject"] = subject }
    if let message { node.attributes["data-share-message"] = message }
    let item = self.item, subject = self.subject, message = self.message
    let share: @MainActor () -> Void = { if let item { ShareRuntime.share(item: item, subject: subject, message: message) } }
    if context.environment.isEnabled, item != nil {
      node.events["click"] = _EventHandler(name: "click", action: share)
    } else {
      node.attributes["disabled"] = "disabled"
      node.attributes["aria-disabled"] = "true"
    }
    let child = _renderButtonLabel(label, role: nil, action: share, node: node, context: context, plainKey: _FiberKey("label"))
    _applyButtonVisibleShape(child, to: node)
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

// MARK: - Accessibility metadata

public struct AccessibilityTraits: OptionSet, Hashable, Sendable {
  @_spi(Renderer) public let rawValue: UInt64
  @_spi(Renderer) public init(rawValue: UInt64) { self.rawValue = rawValue }
  public static let isButton = AccessibilityTraits(rawValue: 1 << 0)
  public static let isHeader = AccessibilityTraits(rawValue: 1 << 1)
  public static let isLink = AccessibilityTraits(rawValue: 1 << 2)
  public static let isSelected = AccessibilityTraits(rawValue: 1 << 3)
  package static let isDisabled = AccessibilityTraits(rawValue: 1 << 4)
  public static let updatesFrequently = AccessibilityTraits(rawValue: 1 << 5)
  public static let isImage = AccessibilityTraits(rawValue: 1 << 6)
}

// MARK: - Modern change/submit callbacks

// MARK: - Browser-neutral Canvas drawing

public enum ColorRenderingMode: Hashable, Sendable { case nonLinear, linear, extendedLinear 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  package var rawValue: String {
    switch self {
    case .nonLinear: "nonLinear"
    case .linear: "linear"
    case .extendedLinear: "extendedLinear"
    }
  }
}

/// A compact intermediate representation for Canvas drawing.  It contains no
/// DOM or JavaScript values; browser and native hosts can replay the same
/// commands using their preferred backend.
@_spi(Renderer) public struct _CanvasColorStop: Hashable, Sendable {
  public let color: String
  public let location: Double
  public init(color: String, location: Double) {
    self.color = color
    self.location = location.isFinite ? min(1, max(0, location)) : 0
  }
}

@_spi(Renderer) public enum _CanvasShading: Sendable {
  case color(String)
  case linear(stops: [_CanvasColorStop], start: CGPoint, end: CGPoint)
  case radial(stops: [_CanvasColorStop], center: CGPoint, startRadius: Double, endRadius: Double, endCenter: CGPoint)
  case angular(stops: [_CanvasColorStop], center: CGPoint, startAngle: Double, endAngle: Double)
  /// An image tiled over the painted area. `origin` anchors the tile grid, `sourceRect` is a
  /// unit-square region of the image, and `scale` multiplies the image's native size.
  case tiled(source: String, origin: CGPoint, sourceRect: CGRect, scale: Double)
  /// A hierarchical `ShapeStyle` level (0 is the foreground, 1 `.secondary`, ...). It resolves to the
  /// inherited foreground color mixed to that level, as `HierarchicalShapeStyle` paints it.
  case level(Int)
  /// `GraphicsContext.Shading.palette(_:)`: entry `min(level, count - 1)` supplies level `level`.
  case palette([_CanvasShading])
  /// A gradient from `Shading.style(_:)` whose unit points are resolved against the bounds of the path it paints.
  case unitGradient(_CanvasUnitGradient)
}

/// A gradient in unit coordinates of the painted path's bounds (`Shading.style(_:)`).
@_spi(Renderer) public enum _CanvasUnitGradient: Sendable {
  case linear(stops: [_CanvasColorStop], start: UnitPoint, end: UnitPoint)
  case radial(stops: [_CanvasColorStop], center: UnitPoint, startRadius: Double, endRadius: Double)
  case angular(stops: [_CanvasColorStop], center: UnitPoint, startAngle: Double, endAngle: Double)
}

@_spi(Renderer) public enum _CanvasCommand: Sendable {
  case fill(path: [String], shading: _CanvasShading, eoFill: Bool)
  case stroke(path: [String], shading: _CanvasShading, style: StrokeStyle)
  case clip(path: [String], eoFill: Bool)
  case save
  case restore
  case translate(x: Double, y: Double)
  case scale(x: Double, y: Double)
  case rotate(radians: Double)
  case setTransform(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double)
  case opacity(Double)
  case blendMode(GraphicsContext.BlendMode)
  /// The canvas `filter` of the drawing state: the CSS filter functions drawn after it are filtered by, or `none`.
  case filter(String)
  case text(String, point: CGPoint, anchor: UnitPoint, shading: _CanvasShading, font: String)
  case image(source: String, rect: CGRect?, point: CGPoint?, anchor: UnitPoint)
  /// A tagged symbol view (or a system image) as HTML markup, drawn by the host as an image of its own layout.
  case symbol(markup: String, fallback: String, point: CGPoint, anchor: UnitPoint, font: String, color: String)
  /// Glyphs of a laid-out text run (`TextRenderer`), drawn from their baseline origin with the run's CSS font, color and
  /// letter spacing; a right-to-left run is drawn ending at `x`.
  case glyphs(String, x: Double, y: Double, font: String, color: String, spacing: Double, rightToLeft: Bool, paint: String)
  /// An underline or strikethrough of a text run, a rectangle `thickness` high centered on `y`, from `x0` to `x1`.
  case textDecoration(x0: Double, x1: Double, y: Double, thickness: Double, color: String)
  /// Back to the canvas's initial state (no transform, clip, opacity or blend mode), for a copy of a context that
  /// draws with a state of its own.
  case resetState
}

/// The SwiftUI-shaped GraphicsContext surface.  Mutations append to a
/// backend-neutral command recorder; no browser state is created while a view
/// is being evaluated.
public struct GraphicsContext {
  /// Options for gradient shadings. `repeat` and `mirror` continue the ramp
  /// beyond its geometry; Canvas 2D cannot tile a gradient, so the shading is
  /// expanded into an equivalent padded gradient when it is drawn.
  public struct GradientOptions: OptionSet, Sendable {
    public typealias RawValue = UInt32
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let `repeat` = GradientOptions(rawValue: 1 << 0)
    public static let mirror = GradientOptions(rawValue: 1 << 1)
    public static let linearColor = GradientOptions(rawValue: 1 << 2)
    public typealias ArrayLiteralElement = GradientOptions
    public typealias Element = GradientOptions
  }

  /// Apple's `GraphicsContext.BlendMode`: the operator a context composites with. Its raw value is CoreGraphics'
  /// `CGBlendMode`. The canvas has no `clear` operator: the host draws a fill or stroke in clear mode opaque with
  /// `destination-out`, which erases to transparency whatever the source alpha. `plusDarker` draws as `darken`.
  public struct BlendMode: RawRepresentable, Equatable, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static var normal: BlendMode { BlendMode(rawValue: 0) }
    public static var multiply: BlendMode { BlendMode(rawValue: 1) }
    public static var screen: BlendMode { BlendMode(rawValue: 2) }
    public static var overlay: BlendMode { BlendMode(rawValue: 3) }
    public static var darken: BlendMode { BlendMode(rawValue: 4) }
    public static var lighten: BlendMode { BlendMode(rawValue: 5) }
    public static var colorDodge: BlendMode { BlendMode(rawValue: 6) }
    public static var colorBurn: BlendMode { BlendMode(rawValue: 7) }
    public static var softLight: BlendMode { BlendMode(rawValue: 8) }
    public static var hardLight: BlendMode { BlendMode(rawValue: 9) }
    public static var difference: BlendMode { BlendMode(rawValue: 10) }
    public static var exclusion: BlendMode { BlendMode(rawValue: 11) }
    public static var hue: BlendMode { BlendMode(rawValue: 12) }
    public static var saturation: BlendMode { BlendMode(rawValue: 13) }
    public static var color: BlendMode { BlendMode(rawValue: 14) }
    public static var luminosity: BlendMode { BlendMode(rawValue: 15) }
    public static var clear: BlendMode { BlendMode(rawValue: 16) }
    public static var copy: BlendMode { BlendMode(rawValue: 17) }
    public static var sourceIn: BlendMode { BlendMode(rawValue: 18) }
    public static var sourceOut: BlendMode { BlendMode(rawValue: 19) }
    public static var sourceAtop: BlendMode { BlendMode(rawValue: 20) }
    public static var destinationOver: BlendMode { BlendMode(rawValue: 21) }
    public static var destinationIn: BlendMode { BlendMode(rawValue: 22) }
    public static var destinationOut: BlendMode { BlendMode(rawValue: 23) }
    public static var destinationAtop: BlendMode { BlendMode(rawValue: 24) }
    public static var xor: BlendMode { BlendMode(rawValue: 25) }
    public static var plusDarker: BlendMode { BlendMode(rawValue: 26) }
    public static var plusLighter: BlendMode { BlendMode(rawValue: 27) }

    /// The `globalCompositeOperation` the canvas host sets for this mode.
    fileprivate var canvasOperation: String {
      switch rawValue {
      case 1: "multiply"
      case 2: "screen"
      case 3: "overlay"
      case 4: "darken"
      case 5: "lighten"
      case 6: "color-dodge"
      case 7: "color-burn"
      case 8: "soft-light"
      case 9: "hard-light"
      case 10: "difference"
      case 11: "exclusion"
      case 12: "hue"
      case 13: "saturation"
      case 14: "color"
      case 15: "luminosity"
      case 16: "clear"
      case 17: "copy"
      case 18: "source-in"
      case 19: "source-out"
      case 20: "source-atop"
      case 21: "destination-over"
      case 22: "destination-in"
      case 23: "destination-out"
      case 24: "destination-atop"
      case 25: "xor"
      case 26: "darken"
      case 27: "lighter"
      default: "source-over"
      }
    }
  }

  /// Options of a shadow filter. The canvas draws a shadow with its object, so `shadowAbove`, `shadowOnly`,
  /// `invertsAlpha` and `disablesGroup` are accepted but not drawn differently.
  public struct ShadowOptions: OptionSet, Sendable {
    public typealias RawValue = UInt32
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let shadowAbove = ShadowOptions(rawValue: 1 << 0)
    public static let shadowOnly = ShadowOptions(rawValue: 1 << 1)
    public static let invertsAlpha = ShadowOptions(rawValue: 1 << 2)
    public static let disablesGroup = ShadowOptions(rawValue: 1 << 3)
    public typealias ArrayLiteralElement = ShadowOptions
    public typealias Element = ShadowOptions
  }

  /// Options of a blur filter. The canvas blur is always a plain Gaussian, so these have no effect.
  public struct BlurOptions: OptionSet, Sendable {
    public typealias RawValue = UInt32
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let opaque = BlurOptions(rawValue: 1 << 0)
    public static let dithersResult = BlurOptions(rawValue: 1 << 1)
    public typealias ArrayLiteralElement = BlurOptions
    public typealias Element = BlurOptions
  }

  /// Options of `addFilter(_:options:)`. The canvas filters in sRGB, so `linearColor` has no effect.
  public struct FilterOptions: OptionSet, Sendable {
    public typealias RawValue = UInt32
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let linearColor = FilterOptions(rawValue: 1 << 0)
    public typealias ArrayLiteralElement = FilterOptions
    public typealias Element = FilterOptions
  }

  /// Apple's `GraphicsContext.Filter`: an effect `addFilter(_:options:)` applies to what the context draws afterwards.
  /// Each filter is one CSS filter function, which is how the canvas filters. `colorMultiply`, `alphaThreshold`,
  /// `colorMatrix`, `luminanceToAlpha`, `alphaMultiply` and the shader filters are not provided: the canvas filter
  /// has no function for them, and an SVG filter would need markup in the page.
  public struct Filter: Sendable {
    fileprivate let css: String
    fileprivate init(css: String) { self.css = css }

    /// A drop shadow of the drawing. Its blur follows the framework's shadow convention (`box-shadow` blurs by twice
    /// the radius). `blendMode` and `options` are not drawn: a CSS drop shadow composites normally.
    public static func shadow(
      color: Color = Color(.sRGBLinear, red: 0, green: 0, blue: 0, opacity: 0.33),
      radius: CGFloat,
      x: CGFloat = 0,
      y: CGFloat = 0,
      blendMode: GraphicsContext.BlendMode = .normal,
      options: GraphicsContext.ShadowOptions = ShadowOptions()
    ) -> Filter {
      Filter(css: "drop-shadow(\(_pathNumber(x))px \(_pathNumber(y))px \(_pathNumber(max(0, radius) * 2))px \(color.cssValue))")
    }
    public static func blur(radius: CGFloat, options: GraphicsContext.BlurOptions = BlurOptions()) -> Filter {
      Filter(css: "blur(\(_pathNumber(max(0, radius)))px)")
    }
    /// The canvas brightness multiplies, so `amount` is added to 1, as the framework's `brightness(_:)` modifier does.
    public static func brightness(_ amount: Double) -> Filter { Filter(css: "brightness(\(_pathNumber(1 + amount)))") }
    public static func contrast(_ amount: Double) -> Filter { Filter(css: "contrast(\(_pathNumber(amount)))") }
    public static func saturation(_ amount: Double) -> Filter { Filter(css: "saturate(\(_pathNumber(amount)))") }
    public static func grayscale(_ amount: Double) -> Filter { Filter(css: "grayscale(\(_pathNumber(amount)))") }
    public static func hueRotation(_ angle: Angle) -> Filter { Filter(css: "hue-rotate(\(_pathNumber(angle.radians))rad)") }
    public static func colorInvert(_ amount: Double = 1) -> Filter { Filter(css: "invert(\(_pathNumber(amount)))") }
  }

  public struct Shading: Sendable {
    fileprivate let storage: _CanvasShading
    fileprivate let spread: _GradientSpread
    fileprivate init(storage: _CanvasShading, spread: _GradientSpread = .pad) {
      self.storage = storage
      self.spread = spread
    }
    public static func color(_ color: Color) -> Shading { Shading(storage: .color(color.cssValue)) }
    public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) -> Shading {
      color(Color(colorSpace, red: red, green: green, blue: blue, opacity: opacity))
    }
    public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) -> Shading {
      color(Color(colorSpace, red: white, green: white, blue: white, opacity: opacity))
    }
    /// Apple's `GraphicsContext.Shading.palette(_:)`. Level `n` of the shaded content takes entry
    /// `min(n, count - 1)`; a fill or stroke paints with level 0, the first entry.
    public static func palette(_ array: [GraphicsContext.Shading]) -> Shading {
      Shading(storage: .palette(array.map { $0.storage }))
    }
    /// Apple's `GraphicsContext.Shading.foreground`: the inherited foreground style (level 0).
    public static var foreground: Shading { Shading(storage: .level(0)) }
    /// Apple's `GraphicsContext.Shading.style(_:)`. Hierarchical levels and foreground keep their level; solid colors
    /// are painted as-is; gradients resolve their unit points against the bounds of each path they paint.
    public static func style<S: ShapeStyle>(_ style: S) -> Shading {
      if let level = style as? HierarchicalShapeStyle { return Shading(storage: .level(level.level)) }
      if style is ForegroundStyle { return Shading(storage: .level(0)) }
      if let gradient = style as? LinearGradient {
        return Shading(storage: .unitGradient(.linear(stops: _canvasStops(gradient.gradient), start: gradient.startPoint, end: gradient.endPoint)))
      }
      if let gradient = style as? RadialGradient {
        return Shading(storage: .unitGradient(.radial(stops: _canvasStops(gradient.gradient), center: gradient.center, startRadius: gradient.startRadius, endRadius: gradient.endRadius)))
      }
      if let gradient = style as? AngularGradient {
        return Shading(storage: .unitGradient(.angular(stops: _canvasStops(gradient.gradient), center: gradient.center, startAngle: gradient.startAngle.radians, endAngle: gradient.endAngle.radians)))
      }
      return Shading(storage: .color(style._swiftUIWebSolidColor?.cssValue ?? style._swiftUIWebCSSValue))
    }
    // Color-style conveniences keep the original SwiftUIWeb Canvas spelling
    // (`with: .blue`) source-compatible while `.color(...)` remains the
    // SwiftUI GraphicsContext form.
    package static let black = Shading.color(.black)
    package static let white = Shading.color(.white)
    package static let red = Shading.color(.red)
    package static let orange = Shading.color(.orange)
    package static let yellow = Shading.color(.yellow)
    package static let green = Shading.color(.green)
    package static let blue = Shading.color(.blue)
    package static let purple = Shading.color(.purple)
    package static let gray = Shading.color(.gray)
    package static let clear = Shading.color(.clear)
    public static func linearGradient(
      _ gradient: Gradient,
      startPoint: CGPoint,
      endPoint: CGPoint,
      options: GraphicsContext.GradientOptions = GraphicsContext.GradientOptions()
    ) -> Shading {
      Shading(storage: .linear(stops: _canvasStops(gradient), start: startPoint, end: endPoint), spread: _GradientSpread(options))
    }
    /// Tiles `image` across the painted area, as SwiftUI's `tiledImage` does.
    public static func linearGradient(
      _ gradient: AnyGradient,
      startPoint: CGPoint,
      endPoint: CGPoint,
      options: GraphicsContext.GradientOptions = GraphicsContext.GradientOptions()
    ) -> Shading {
      linearGradient(gradient.gradient, startPoint: startPoint, endPoint: endPoint, options: options)
    }
    public static func tiledImage(
      _ image: Image,
      origin: CGPoint = _SwiftUIWebGeometryDefaults.zeroPoint,
      sourceRect: CGRect = _SwiftUIWebGeometryDefaults.unitRect,
      scale: CGFloat = 1
    ) -> Shading {
      Shading(storage: .tiled(source: _ImageAssets.marked(image.source, allowsRemote: image.allowsRemoteSource), origin: origin, sourceRect: sourceRect, scale: scale))
    }
    public static func radialGradient(
      _ gradient: Gradient,
      center: CGPoint,
      startRadius: CGFloat,
      endRadius: CGFloat,
      options: GraphicsContext.GradientOptions = GraphicsContext.GradientOptions()
    ) -> Shading {
      Shading(storage: .radial(stops: _canvasStops(gradient), center: center, startRadius: startRadius, endRadius: endRadius, endCenter: center), spread: _GradientSpread(options))
    }
    public static func radialGradient(
      _ gradient: Gradient,
      startCenter: CGPoint,
      startRadius: CGFloat,
      endCenter: CGPoint,
      endRadius: CGFloat,
      options: GraphicsContext.GradientOptions = GraphicsContext.GradientOptions()
    ) -> Shading {
      Shading(storage: .radial(stops: _canvasStops(gradient), center: startCenter, startRadius: startRadius, endRadius: endRadius, endCenter: endCenter), spread: _GradientSpread(options))
    }
    public static func radialGradient(
      _ gradient: AnyGradient,
      center: CGPoint,
      startRadius: CGFloat,
      endRadius: CGFloat,
      options: GraphicsContext.GradientOptions = GraphicsContext.GradientOptions()
    ) -> Shading {
      radialGradient(gradient.gradient, center: center, startRadius: startRadius, endRadius: endRadius, options: options)
    }
    public static func radialGradient(
      _ gradient: AnyGradient,
      startCenter: CGPoint,
      startRadius: CGFloat,
      endCenter: CGPoint,
      endRadius: CGFloat,
      options: GraphicsContext.GradientOptions = GraphicsContext.GradientOptions()
    ) -> Shading {
      radialGradient(gradient.gradient, startCenter: startCenter, startRadius: startRadius, endCenter: endCenter, endRadius: endRadius, options: options)
    }
    public static func conicGradient(
      _ gradient: Gradient,
      center: CGPoint,
      angle: Angle = Angle(),
      options: GraphicsContext.GradientOptions = GraphicsContext.GradientOptions()
    ) -> Shading {
      Shading(storage: .angular(stops: _canvasStops(gradient), center: center, startAngle: angle.radians, endAngle: angle.radians), spread: _GradientSpread(options))
    }
    public static func conicGradient(
      _ gradient: AnyGradient,
      center: CGPoint,
      angle: Angle = Angle(),
      options: GraphicsContext.GradientOptions = GraphicsContext.GradientOptions()
    ) -> Shading {
      conicGradient(gradient.gradient, center: center, angle: angle, options: options)
    }
    package static func angularGradient(_ gradient: Gradient, center: CGPoint, startAngle: Angle = .zero, endAngle: Angle = .zero) -> Shading {
      Shading(storage: .angular(stops: _canvasStops(gradient), center: center, startAngle: startAngle.radians, endAngle: endAngle.radians))
    }
  }

  /// Apple's `GraphicsContext.ResolvedText`: text resolved against an environment. Its `shading` paints the
  /// uncolored text; the default is `.foreground`, the environment's foreground style.
  public struct ResolvedText: Sendable {
    fileprivate let value: String
    fileprivate let color: String
    fileprivate let font: String
    fileprivate let fontSize: Double
    fileprivate var storage: _CanvasShading = .level(0)
    public var shading: Shading {
      get { Shading(storage: storage) }
      set { storage = newValue.storage }
    }
    /// Browser text measures from its font size, so the width is an estimate of the characters' advance.
    public func measure(in proposedSize: CGSize) -> CGSize {
      let width = min(proposedSize.width, Double(value.count) * fontSize * 0.55)
      return CGSize(width: max(0, width), height: min(proposedSize.height, fontSize * 1.2))
    }
    /// The baseline sits at the estimated ascent (0.8em) of the first line. Text is a single line here, so the last
    /// baseline is the first one.
    public func firstBaseline(in size: CGSize) -> CGFloat { CGFloat(fontSize * 0.8) }
    public func lastBaseline(in size: CGSize) -> CGFloat { firstBaseline(in: size) }
  }

  /// Apple's `GraphicsContext.ResolvedImage`. A system image is a template drawn with the foreground style by
  /// default; a raster image keeps its own colors, so its `shading` is nil.
  public struct ResolvedImage: Sendable {
    fileprivate let source: String
    /// The glyph markup of a system image, or nil for a raster image.
    fileprivate let symbolMarkup: String?
    fileprivate let font: String
    fileprivate let color: String
    /// A system image is one font-sized square, as the browser draws its symbol glyphs. A raster image's natural size
    /// is only known after it decodes, so it reports zero.
    public let size: CGSize
    public let baseline: CGFloat
    public var shading: Shading?
  }

  /// Apple's `GraphicsContext.ResolvedSymbol`: a child view tagged in the `Canvas` symbols, resolved against the
  /// environment. The browser lays the view out when it draws it, so `size` is the frame the view declares, or zero.
  public struct ResolvedSymbol: Sendable {
    fileprivate let fallback: String
    fileprivate let markup: String
    fileprivate let font: String
    fileprivate let color: String
    public let size: CGSize
  }

  /// Symbol definitions for `Canvas`. A tagged view keeps its markup, which a 2D context draws as an image.
  /// Hosts without a renderer draw the fallback label.
  package struct Symbols: Hashable, Sendable {
    fileprivate var entries: [String: _CanvasSymbolEntry] = .init()
    package init() {}
    package mutating func add<ID: Hashable, V: View>(_ view: V, id: ID) {
      let fallback: String
      if let text = view as? Text { fallback = text.value }
      else if let image = view as? Image { fallback = image.alt ?? image.source }
      else { fallback = _swiftUIWebDescribe(view) }
      entries[fiberKeyDescription(_FiberKey(id))] = _CanvasSymbolEntry(fallback: fallback, markup: _canvasEscapeHTML(fallback), size: .zero)
    }
    package mutating func add<ID: Hashable>(_ label: String, id: ID) {
      entries[fiberKeyDescription(_FiberKey(id))] = _CanvasSymbolEntry(fallback: label, markup: _canvasEscapeHTML(label), size: .zero)
    }
    package subscript<ID: Hashable>(id: ID) -> String? {
      get { entries[fiberKeyDescription(_FiberKey(id))]?.fallback }
      set {
        guard let newValue else { entries[fiberKeyDescription(_FiberKey(id))] = nil; return }
        add(newValue, id: id)
      }
    }
  }

  fileprivate var recorder: _CanvasRecorder
  fileprivate var symbols: [String: _CanvasSymbolEntry]
  fileprivate var canvasSize: SwiftUIWebCanvasSize
  fileprivate var environmentFont: Font
  fileprivate var environmentColor: Color
  /// The paints of hierarchical levels 1 and 2: the foreground styles `foregroundStyle` set, or their color mixes.
  fileprivate var secondaryPaint: String
  fileprivate var tertiaryPaint: String

  package init() {
    recorder = _CanvasRecorder()
    symbols = .init()
    canvasSize = SwiftUIWebCanvasSize(width: 300, height: 150)
    environmentFont = .body
    environmentColor = .primary
    secondaryPaint = HierarchicalShapeStyle(level: 1)._swiftUIWebCSSValue
    tertiaryPaint = HierarchicalShapeStyle(level: 2)._swiftUIWebCSSValue
  }

  fileprivate init(size: SwiftUIWebCanvasSize, environment: EnvironmentValues, symbols: Symbols) {
    recorder = _CanvasRecorder()
    self.symbols = symbols.entries
    canvasSize = size
    environmentFont = environment.font
    environmentColor = environment.foregroundColor
    secondaryPaint = environment._foregroundSecondaryPaint ?? HierarchicalShapeStyle(level: 1)._swiftUIWebCSSValue
    tertiaryPaint = environment._foregroundTertiaryPaint ?? HierarchicalShapeStyle(level: 2)._swiftUIWebCSSValue
  }

  /// Replaces hierarchical levels 1 and 2 with the paints this context's environment sets for them.
  fileprivate func _levelStorage(_ shading: _CanvasShading) -> _CanvasShading {
    switch shading {
    case .level(1): return .color(secondaryPaint)
    case .level(2): return .color(tertiaryPaint)
    case .palette(let entries): return .palette(entries.map { _levelStorage($0) })
    default: return shading
    }
  }
  fileprivate func _levels(_ shading: Shading) -> Shading {
    Shading(storage: _levelStorage(shading.storage), spread: shading.spread)
  }

  public var opacity: Double {
    get { recorder.opacity }
    set { recorder.sync(); recorder.opacity = min(1, max(0, newValue)); recorder.change(.opacity(recorder.opacity)) }
  }
  public var blendMode: BlendMode {
    get { recorder.blendMode }
    set { recorder.sync(); recorder.blendMode = newValue; recorder.change(.blendMode(newValue)) }
  }
  public var transform: CGAffineTransform {
    get { CGAffineTransform(a: recorder.a, b: recorder.b, c: recorder.c, d: recorder.d, tx: recorder.tx, ty: recorder.ty) }
    set {
      recorder.sync()
      recorder.a = newValue.a; recorder.b = newValue.b; recorder.c = newValue.c; recorder.d = newValue.d; recorder.tx = newValue.tx; recorder.ty = newValue.ty
      recorder.change(.setTransform(a: recorder.a, b: recorder.b, c: recorder.c, d: recorder.d, tx: recorder.tx, ty: recorder.ty))
    }
  }

  /// Apple's `concatenate(_:)`: `matrix` is applied to the user space before the current transform, as Core Graphics
  /// concatenates a matrix onto the CTM (the current transform becomes `matrix` x CTM).
  public mutating func concatenate(_ matrix: CGAffineTransform) {
    let a = matrix.a * recorder.a + matrix.b * recorder.c
    let b = matrix.a * recorder.b + matrix.b * recorder.d
    let c = matrix.c * recorder.a + matrix.d * recorder.c
    let d = matrix.c * recorder.b + matrix.d * recorder.d
    let tx = matrix.tx * recorder.a + matrix.ty * recorder.c + recorder.tx
    let ty = matrix.tx * recorder.b + matrix.ty * recorder.d + recorder.ty
    recorder.sync()
    recorder.a = a; recorder.b = b; recorder.c = c; recorder.d = d; recorder.tx = tx; recorder.ty = ty
    recorder.change(.setTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty))
  }

  /// Apple's `addFilter(_:options:)`: the filter applies to what this context draws from now on, and to its copies
  /// (a layer's content included). Filters chain in the order they are added.
  public mutating func addFilter(_ filter: GraphicsContext.Filter, options: GraphicsContext.FilterOptions = FilterOptions()) {
    recorder.sync()
    recorder.filter = recorder.filter.isEmpty ? filter.css : recorder.filter + " " + filter.css
    recorder.change(.filter(recorder.filter))
  }

  // SwiftUI's GraphicsContext draws `Path` values. The Shape- and Color-based
  // overloads are SwiftUIWeb conveniences that have no Apple counterpart, so
  // they are package-scoped and forward to the Path forms.
  public mutating func fill(_ path: Path, with shading: GraphicsContext.Shading, style: FillStyle = FillStyle()) {
    let resolved = _spreadExpanded(_levels(shading).flattened(in: path.boundingRect), bounds: path.boundingRect)
    recorder.emit(.fill(path: path.commands, shading: resolved, eoFill: style.isEOFilled))
  }
  public mutating func stroke(_ path: Path, with shading: GraphicsContext.Shading, style: StrokeStyle) {
    let margin = style.lineWidth
    let resolved = _spreadExpanded(_levels(shading).flattened(in: path.boundingRect), bounds: path.boundingRect.insetBy(dx: -margin, dy: -margin))
    recorder.emit(.stroke(path: path.commands, shading: resolved, style: style))
  }
  public mutating func stroke(_ path: Path, with shading: GraphicsContext.Shading, lineWidth: Double = 1) {
    stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
  }
  package mutating func fill<S: Shape>(_ shape: S, with shading: Shading, style: FillStyle = FillStyle()) {
    fill(_canvasPath(for: shape, in: canvasSize), with: shading, style: style)
  }
  package mutating func fill<S: Shape, Style: ShapeStyle>(_ shape: S, with style: Style, style fillStyle: FillStyle = FillStyle()) {
    fill(shape, with: Shading(storage: _canvasShading(style, in: canvasSize)), style: fillStyle)
  }
  package mutating func stroke<S: Shape>(_ shape: S, with shading: Shading, style: StrokeStyle = StrokeStyle()) {
    stroke(_canvasPath(for: shape, in: canvasSize), with: shading, style: style)
  }
  package mutating func stroke<S: Shape, Style: ShapeStyle>(_ shape: S, with style: Style, style strokeStyle: StrokeStyle = StrokeStyle()) {
    stroke(shape, with: Shading(storage: _canvasShading(style, in: canvasSize)), style: strokeStyle)
  }
  package mutating func stroke<S: Shape>(_ shape: S, with color: Color, lineWidth: Double = 1) {
    stroke(shape, with: Shading.color(color), style: StrokeStyle(lineWidth: lineWidth))
  }
  public mutating func clip(to path: Path, style: FillStyle = FillStyle()) {
    recorder.change(.clip(path: path.commands, eoFill: style.isEOFilled))
    recorder.clips.append(_CanvasClip(path: path.commands, eoFill: style.isEOFilled, transform: (recorder.a, recorder.b, recorder.c, recorder.d, recorder.tx, recorder.ty)))
  }
  public mutating func drawLayer(content: (inout GraphicsContext) -> Void) {
    recorder.emit(.save)
    let saved = recorder
    let resets = recorder.sink.resets
    content(&self)
    recorder.sink.commands.append(.restore)
    recorder = saved
    // A copy that drew in the layer reset the canvas: the restore after it is not this context's state any more.
    recorder.sink.current = recorder.sink.resets == resets ? saved.stateID : -1
  }
  public mutating func translateBy(x: Double, y: Double) {
    recorder.change(.translate(x: x, y: y)); recorder.tx += recorder.a * x + recorder.c * y; recorder.ty += recorder.b * x + recorder.d * y
  }
  public mutating func scaleBy(x: Double, y: Double) {
    recorder.change(.scale(x: x, y: y)); recorder.a *= x; recorder.b *= x; recorder.c *= y; recorder.d *= y
  }
  public mutating func rotate(by angle: Angle) {
    recorder.change(.rotate(radians: angle.radians))
    let cosine = _canvasCosine(angle.radians)
    let sine = _canvasSine(angle.radians)
    let a = recorder.a * cosine + recorder.c * sine
    let b = recorder.b * cosine + recorder.d * sine
    let c = recorder.c * cosine - recorder.a * sine
    let d = recorder.d * cosine - recorder.b * sine
    recorder.a = a; recorder.b = b; recorder.c = c; recorder.d = d
  }
  package mutating func withCGContext(_ action: (inout GraphicsContext) -> Void) { action(&self) }

  public func resolve(_ text: Text) -> ResolvedText {
    ResolvedText(value: text.value, color: environmentColor.cssValue, font: _canvasFont(environmentFont), fontSize: _canvasFontSize(environmentFont))
  }
  public func resolve(_ image: Image) -> ResolvedImage {
    let font = _canvasFont(environmentFont), color = environmentColor.cssValue
    guard image.source.hasPrefix("symbol:") else {
      // The source keeps the remote permission of an `Image(_:alt:)` or an `AsyncImage` load (see `_ImageAssets.marked`).
      return ResolvedImage(source: _ImageAssets.marked(image.source, allowsRemote: image.allowsRemoteSource), symbolMarkup: nil, font: font, color: color, size: CGSize(width: 0, height: 0), baseline: 0, shading: nil)
    }
    let name = String(image.source.dropFirst("symbol:".count))
    let side = CGFloat(_canvasFontSize(environmentFont))
    let glyph = _canvasEscapeHTML(_systemSymbolGlyph(name))
    let markup = "<span class=\"symbol-icon\" data-symbol=\"" + _canvasEscapeHTML(name) + "\">" + glyph + "</span>"
    return ResolvedImage(source: image.source, symbolMarkup: markup, font: font, color: color, size: CGSize(width: side, height: side), baseline: side, shading: .foreground)
  }
  public func resolveSymbol<ID: Hashable>(id: ID) -> ResolvedSymbol? {
    guard let entry = symbols[fiberKeyDescription(_FiberKey(id))] else { return nil }
    return ResolvedSymbol(fallback: entry.fallback, markup: entry.markup, font: _canvasFont(environmentFont), color: environmentColor.cssValue, size: entry.size)
  }
  public mutating func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
    draw(resolve(text), at: point, anchor: anchor)
  }
  public mutating func draw(_ text: GraphicsContext.ResolvedText, at point: CGPoint, anchor: UnitPoint = .center) {
    let box = _canvasBox(text.measure(in: CGSize(width: Double.infinity, height: Double.infinity)), at: point, anchor: anchor)
    let paint = _canvasForeground(_levelStorage(text.storage), color: text.color, in: box)
    recorder.emit(.text(text.value, point: point, anchor: anchor, shading: paint, font: text.font))
  }
  public mutating func draw(_ text: Text, in rect: CGRect) {
    draw(resolve(text), in: rect)
  }
  /// Text is laid out from the rectangle's top-left corner; its wrapping is not modelled, so only the origin is used.
  public mutating func draw(_ text: GraphicsContext.ResolvedText, in rect: CGRect) {
    draw(text, at: rect.origin, anchor: .topLeading)
  }
  public mutating func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
    draw(resolve(image), at: point, anchor: anchor)
  }
  public mutating func draw(_ image: GraphicsContext.ResolvedImage, at point: CGPoint, anchor: UnitPoint = .center) {
    guard let markup = image.symbolMarkup else {
      recorder.emit(.image(source: image.source, rect: nil, point: point, anchor: anchor))
      return
    }
    let box = _canvasBox(image.size, at: point, anchor: anchor)
    let color = _canvasForeground(_levelStorage(image.shading?.storage ?? .level(0)), color: image.color, in: box)
    recorder.emit(.symbol(markup: markup, fallback: image.source, point: point, anchor: anchor, font: image.font, color: _canvasColorValue(color, fallback: image.color)))
  }
  public mutating func draw(_ image: GraphicsContext.ResolvedImage, in rect: CGRect, style: FillStyle = FillStyle()) {
    if image.symbolMarkup != nil {
      draw(image, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
      return
    }
    recorder.emit(.image(source: image.source, rect: rect, point: nil, anchor: .topLeading))
  }
  public mutating func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) {
    draw(resolve(image), in: rect, style: style)
  }
  public mutating func draw(_ symbol: GraphicsContext.ResolvedSymbol, at point: CGPoint, anchor: UnitPoint = .center) {
    recorder.emit(.symbol(markup: symbol.markup, fallback: symbol.fallback, point: point, anchor: anchor, font: symbol.font, color: symbol.color))
  }
  /// The symbol is centered in the rectangle, the way a view fills its frame when it does not stretch.
  public mutating func draw(_ symbol: GraphicsContext.ResolvedSymbol, in rect: CGRect) {
    draw(symbol, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
  }

  fileprivate var commands: [_CanvasCommand] { recorder.commands }

  /// Records glyphs of a laid-out text run at their baseline (`GraphicsContext.draw(_: Text.Layout.Line)` and its run and
  /// slice forms). `paint` is the canvas shading of a run painted with a gradient, as the page measured it (JSON).
  mutating func _drawGlyphs(_ text: String, x: Double, y: Double, font: String, color: String, spacing: Double, rightToLeft: Bool, paint: String = "") {
    guard !text.isEmpty else { return }
    recorder.emit(.glyphs(text, x: x, y: y, font: font, color: color, spacing: spacing, rightToLeft: rightToLeft, paint: paint))
  }

  /// Records an underline or strikethrough of a text run.
  mutating func _drawTextDecoration(x0: Double, x1: Double, y: Double, thickness: Double, color: String) {
    guard x1 > x0, thickness > 0 else { return }
    recorder.emit(.textDecoration(x0: x0, x1: x1, y: y, thickness: thickness, color: color))
  }
}

/// The canvas a `TextRenderer` draws a text into: `size` in points, the drawing translated by `origin` (the display
/// padding), painted by the page's canvas host like a `Canvas` is.
@MainActor func _textRendererCanvas(size: CGSize, origin: CGPoint, environment: EnvironmentValues, draw: (inout GraphicsContext) -> Void) -> _RenderNode {
  var graphics = GraphicsContext(size: size, environment: environment, symbols: GraphicsContext.Symbols())
  if origin.x != 0 || origin.y != 0 { graphics.translateBy(x: Double(origin.x), y: Double(origin.y)) }
  draw(&graphics)
  // The canvas host paints it (`data-draw-canvas`); it has none of the look of a `Canvas` view (`.draw-canvas`).
  let node = _RenderNode.element("canvas")
  node.attributes["data-draw-canvas"] = "true"
  node.attributes["data-text-renderer-canvas"] = "true"
  node.attributes["aria-hidden"] = "true"
  node.attributes["data-canvas-size"] = _pathNumber(Double(size.width)) + "," + _pathNumber(Double(size.height))
  node.attributes["data-canvas-command-count"] = String(graphics.commands.count)
  let fingerprint = _canvasFingerprint(graphics.commands)
  node.attributes["data-canvas-fingerprint"] = fingerprint
  node.attributes["data-canvas-commands"] = _canvasWire(graphics.commands)
  node.styles["position"] = "absolute"
  node.styles["left"] = _pathNumber(-Double(origin.x)) + "px"
  node.styles["top"] = _pathNumber(-Double(origin.y)) + "px"
  node.styles["width"] = _pathNumber(Double(size.width)) + "px"
  node.styles["height"] = _pathNumber(Double(size.height)) + "px"
  node.styles["pointer-events"] = "none"
  node._canvasCommands = graphics.commands
  node._canvasFingerprint = fingerprint
  return node
}

/// The commands a canvas draws, shared by a `GraphicsContext` and its copies: as in SwiftUI, a copy draws into the same
/// canvas with drawing state of its own.
fileprivate final class _CanvasSink {
  var commands: [_CanvasCommand] = []
  /// The drawing state the commands leave the canvas in: the `stateID` of the context that wrote last, or -1 when
  /// none of them knows it (after a layer a copy drew in).
  var current = 0
  var lastID = 0
  var resets = 0
  func newID() -> Int { lastID += 1; return lastID }
}

/// A clip of a context: its path, in the transform the context had when it clipped.
fileprivate struct _CanvasClip {
  let path: [String]
  let eoFill: Bool
  let transform: (Double, Double, Double, Double, Double, Double)
}

/// The drawing state of one `GraphicsContext` value. The commands it writes go to the sink; before writing, a context
/// whose state is not the one the canvas is in (a copy, or the original after a copy drew) puts its own back: a state
/// reset, then its opacity, blend mode, clips and transform. A context that is never copied writes exactly the commands
/// it is asked for.
fileprivate struct _CanvasRecorder {
  let sink = _CanvasSink()
  var stateID = 0
  var opacity: Double = 1
  var blendMode: GraphicsContext.BlendMode = .normal
  var filter = ""
  var a: Double = 1
  var b: Double = 0
  var c: Double = 0
  var d: Double = 1
  var tx: Double = 0
  var ty: Double = 0
  var clips: [_CanvasClip] = []

  var commands: [_CanvasCommand] { sink.commands }

  /// Puts the canvas in this context's state when another context's is there.
  func sync() {
    guard sink.current != stateID else { return }
    sink.resets += 1
    sink.commands.append(.resetState)
    if opacity != 1 { sink.commands.append(.opacity(opacity)) }
    if blendMode != .normal { sink.commands.append(.blendMode(blendMode)) }
    if !filter.isEmpty { sink.commands.append(.filter(filter)) }
    for clip in clips {
      let m = clip.transform
      sink.commands.append(.setTransform(a: m.0, b: m.1, c: m.2, d: m.3, tx: m.4, ty: m.5))
      sink.commands.append(.clip(path: clip.path, eoFill: clip.eoFill))
    }
    if !clips.isEmpty || a != 1 || b != 0 || c != 0 || d != 1 || tx != 0 || ty != 0 {
      sink.commands.append(.setTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty))
    }
    sink.current = stateID
  }

  /// Draws `command` in this context's state.
  func emit(_ command: _CanvasCommand) {
    sync()
    sink.commands.append(command)
  }

  /// Writes `command`, which changes the drawing state, after this context's state: the canvas is in the new state.
  mutating func change(_ command: _CanvasCommand) {
    sync()
    sink.commands.append(command)
    stateID = sink.newID()
    sink.current = stateID
  }
}

/// A compact, host-neutral path recorder.  It intentionally keeps only a
/// semantic command stream in Core; a browser host can turn the commands into
/// SVG/Canvas while WASI/static rendering can still compile and snapshot the
/// surrounding view.  The familiar SwiftUI mutation API is preserved so
/// application-defined shapes do not need a platform-specific fork.
// Keep the default transform construction explicit in terms of CGFloat. On
// Apple platforms `CGAffineTransform` stores CGFloat fields, while the
// WebAssembly fallback aliases CGFloat to Double. Swift 6.4's SIL verifier
// rejects the implicit Double-to-CGFloat aggregate that older compilers
// accepted in default arguments.
@usableFromInline
@inline(__always)
internal func _swiftUIWebIdentityAffineTransform() -> CGAffineTransform {
  CGAffineTransform(
    a: CGFloat(1), b: CGFloat(0), c: CGFloat(0), d: CGFloat(1),
    tx: CGFloat(0), ty: CGFloat(0)
  )
}

public struct Path: Shape, Hashable, Sendable {
  fileprivate var commands: [String]

  public init() { commands = [] }
  public init(_ body: (inout Path) -> ()) {
    self.init()
    body(&self)
  }

  /// SwiftUI-compatible convenience initializers.  Keeping these as command
  /// stream builders means paths created by application code take the exact
  /// same SVG/Canvas realization route as paths assembled incrementally.
  public init(_ rect: CGRect) {
    self.init()
    addRect(rect)
  }

  public init(ellipseIn rect: CGRect) {
    self.init()
    addEllipse(in: rect)
  }

  public init(
    roundedRect rect: CGRect,
    cornerSize: CGSize,
    style: RoundedCornerStyle = .circular
  ) {
    self.init()
    addRoundedRect(in: rect, cornerSize: cornerSize, style: style)
  }

  public init(
    roundedRect rect: CGRect,
    cornerRadius: CGFloat,
    style: RoundedCornerStyle = .circular
  ) {
    self.init(roundedRect: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
  }

  /// Mirrors SwiftUI's cheap emptiness query without exposing the renderer's
  /// internal command representation.
  public var isEmpty: Bool { commands.isEmpty }

  /// SwiftUI's `boundingRect`: the bounds of the path's points, lines, curves and arcs themselves, not of their
  /// control points (a move with nothing after it still counts). A transformed ellipse or rounded rectangle is bounded
  /// by its transformed corners, which is exact for rectangles and loose only for a rotated ellipse.
  public var boundingRect: CGRect {
    var minX = Double.infinity
    var minY = Double.infinity
    var maxX = -Double.infinity
    var maxY = -Double.infinity
    struct Matrix {
      var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0
      func point(_ x: Double, _ y: Double) -> (Double, Double) {
        (a * x + c * y + tx, b * x + d * y + ty)
      }
    }
    func matrix(_ values: _PathNumbers, offset: Int = 0) -> Matrix {
      guard values.count >= offset + 6 else { return Matrix() }
      return Matrix(a: values[offset], b: values[offset + 1], c: values[offset + 2], d: values[offset + 3], tx: values[offset + 4], ty: values[offset + 5])
    }
    func include(_ point: (Double, Double)) {
      minX = min(minX, point.0); minY = min(minY, point.1)
      maxX = max(maxX, point.0); maxY = max(maxY, point.1)
    }
    func includeBox(_ x: Double, _ y: Double, _ width: Double, _ height: Double, by transform: Matrix) {
      include(transform.point(x, y))
      include(transform.point(x + width, y))
      include(transform.point(x + width, y + height))
      include(transform.point(x, y + height))
    }
    // A curve's bounds are its own, not its control points' (as SwiftUI's are): its ends, and the points where the
    // derivative of x or y vanishes inside it. An affine transform maps a Bézier curve to the curve of the mapped
    // control points, so this works in the transformed space.
    func cubicExtrema(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> [Double] {
      let a = -p0 + 3 * p1 - 3 * p2 + p3, b = 2 * (p0 - 2 * p1 + p2), c = p1 - p0
      if abs(a) < 1e-12 { return abs(b) < 1e-12 ? [] : [-c / b] }
      let discriminant = b * b - 4 * a * c
      guard discriminant >= 0 else { return [] }
      let root = discriminant.squareRoot()
      return [(-b + root) / (2 * a), (-b - root) / (2 * a)]
    }
    func includeCubic(_ p0: (Double, Double), _ p1: (Double, Double), _ p2: (Double, Double), _ p3: (Double, Double)) {
      include(p3)
      for t in cubicExtrema(p0.0, p1.0, p2.0, p3.0) + cubicExtrema(p0.1, p1.1, p2.1, p3.1) where t > 0 && t < 1 {
        let u = 1 - t
        let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
        include((w0 * p0.0 + w1 * p1.0 + w2 * p2.0 + w3 * p3.0, w0 * p0.1 + w1 * p1.1 + w2 * p2.1 + w3 * p3.1))
      }
    }
    func includeQuad(_ p0: (Double, Double), _ p1: (Double, Double), _ p2: (Double, Double)) {
      include(p2)
      for (q0, q1, q2) in [(p0.0, p1.0, p2.0), (p0.1, p1.1, p2.1)] {
        let denominator = q0 - 2 * q1 + q2
        guard abs(denominator) > 1e-12 else { continue }
        let t = (q0 - q1) / denominator
        guard t > 0 && t < 1 else { continue }
        let u = 1 - t
        include((u * u * p0.0 + 2 * u * t * p1.0 + t * t * p2.0, u * u * p0.1 + 2 * u * t * p1.1 + t * t * p2.1))
      }
    }

    var transform = Matrix()
    // The current point and the start of the open subpath, in the transformed space; a curve starts at the current point.
    var current: (Double, Double)?
    var subpathStart: (Double, Double)?
    for raw in commands {
      let opcode: String
      if raw.hasPrefix("RRT") { opcode = "RRT" }
      else if raw.hasPrefix("RR") { opcode = "RR" }
      else if raw.hasPrefix("RT") { opcode = "RT" }
      else if raw.hasPrefix("ET") { opcode = "ET" }
      else { opcode = raw.first.map(String.init) ?? "" }
      let values = _parsePathNumbers(raw.dropFirst(opcode.count))
      switch opcode {
      case "M", "L":
        guard values.count >= 2 else { break }
        let point = transform.point(values[0], values[1])
        include(point)
        if opcode == "M" || current == nil { subpathStart = point }
        current = point
      case "C":
        guard values.count >= 6 else { break }
        let control1 = transform.point(values[0], values[1]), control2 = transform.point(values[2], values[3])
        let end = transform.point(values[4], values[5])
        if let start = current { includeCubic(start, control1, control2, end) } else {
          include(control1); include(control2); include(end)
          subpathStart = control1
        }
        current = end
      case "Q":
        guard values.count >= 4 else { break }
        let control = transform.point(values[0], values[1]), end = transform.point(values[2], values[3])
        if let start = current { includeQuad(start, control, end) } else {
          include(control); include(end)
          subpathStart = control
        }
        current = end
      case "Z":
        current = subpathStart
      case "A":
        // The arc itself, not its whole circle: its ends, and the angles in its sweep where the transformed x or y is
        // extreme (x' = a r cos + c r sin is extreme at atan2(c, a), and half a turn on; y' at atan2(d, b)).
        if values.count >= 6 {
          let radius = abs(values[2]), start = values[3]
          let clockwise = values[5] != 0
          let sweep = _directedArcSweep(start: start, end: values[4], clockwise: clockwise)
          let direction: Double = clockwise ? -1 : 1
          func point(at angle: Double) -> (Double, Double) {
            let (cosine, sine) = _pathCosSin(angle)
            return transform.point(values[0] + radius * cosine, values[1] + radius * sine)
          }
          include(point(at: start))
          let end = point(at: start + direction * sweep)
          include(end)
          if current == nil { subpathStart = point(at: start) }
          current = end
          let turn = 2 * Double.pi
          for base in [_tangentAtan2(transform.c, transform.a), _tangentAtan2(transform.d, transform.b)] {
            for candidate in [base, base + Double.pi] {
              var along = ((candidate - start) * direction).truncatingRemainder(dividingBy: turn)
              if along < 0 { along += turn }
              if along <= sweep { include(point(at: candidate)) }
            }
          }
        }
      // A closed shape leaves no current point a curve could start from.
      case "R", "E", "RR":
        if values.count >= 4 { includeBox(values[0], values[1], values[2], values[3], by: transform) }
        current = nil
      case "T":
        if values.count >= 6 { transform = matrix(values) }
      case "RT", "ET":
        if values.count >= 10 { includeBox(values[0], values[1], values[2], values[3], by: matrix(values, offset: 4)) }
        current = nil
      case "RRT":
        if values.count >= 13 { includeBox(values[0], values[1], values[2], values[3], by: matrix(values, offset: 7)) }
        current = nil
      default:
        break
      }
    }
    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return CGRect() }
    let width = max(0, maxX - minX)
    let height = max(0, maxY - minY)
    let x = CGFloat(minX)
    let y = CGFloat(minY)
    let w = CGFloat(width)
    let h = CGFloat(height)
    return CGRect(
      origin: CGPoint(x: x, y: y),
      size: CGSize(width: w, height: h)
    )
  }

  public mutating func move(to point: CGPoint) {
    commands.append("M\(_pathNumber(point.x)),\(_pathNumber(point.y))")
  }
  public mutating func addLine(to point: CGPoint) {
    commands.append("L\(_pathNumber(point.x)),\(_pathNumber(point.y))")
  }
  public mutating func addCurve(
    to point: CGPoint,
    control1: CGPoint,
    control2: CGPoint
  ) {
    commands.append("C\(_pathNumber(control1.x)),\(_pathNumber(control1.y)),\(_pathNumber(control2.x)),\(_pathNumber(control2.y)),\(_pathNumber(point.x)),\(_pathNumber(point.y))")
  }
  public mutating func addQuadCurve(to point: CGPoint, control: CGPoint) {
    commands.append("Q\(_pathNumber(control.x)),\(_pathNumber(control.y)),\(_pathNumber(point.x)),\(_pathNumber(point.y))")
  }
  public mutating func addArc(
    center: CGPoint,
    radius: Double,
    startAngle: Angle,
    endAngle: Angle,
    clockwise: Bool,
    transform: CGAffineTransform = _swiftUIWebIdentityAffineTransform()
  ) {
    var arc = Path()
    arc.commands.append("A\(_pathNumber(center.x)),\(_pathNumber(center.y)),\(_pathNumber(radius)),\(_pathAngleNumber(startAngle.radians)),\(_pathAngleNumber(endAngle.radians)),\(clockwise ? 1 : 0)")
    addPath(arc, transform: transform)
  }
  public mutating func addRelativeArc(
    center: CGPoint,
    radius: Double,
    startAngle: Angle,
    delta: Angle,
    transform: CGAffineTransform = _swiftUIWebIdentityAffineTransform()
  ) {
    addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle + delta, clockwise: false, transform: transform)
  }
  public mutating func addRect(_ rect: CGRect, transform: CGAffineTransform = _swiftUIWebIdentityAffineTransform()) {
    let basic = "\(_pathNumber(rect.origin.x)),\(_pathNumber(rect.origin.y)),\(_pathNumber(rect.size.width)),\(_pathNumber(rect.size.height))"
    if transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1 && transform.tx == 0 && transform.ty == 0 { commands.append("R\(basic)") }
    else { commands.append("RT\(basic),\(_pathNumber(transform.a)),\(_pathNumber(transform.b)),\(_pathNumber(transform.c)),\(_pathNumber(transform.d)),\(_pathNumber(transform.tx)),\(_pathNumber(transform.ty))") }
  }
  public mutating func addEllipse(in rect: CGRect, transform: CGAffineTransform = _swiftUIWebIdentityAffineTransform()) {
    let basic = "\(_pathNumber(rect.origin.x)),\(_pathNumber(rect.origin.y)),\(_pathNumber(rect.size.width)),\(_pathNumber(rect.size.height))"
    if transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1 && transform.tx == 0 && transform.ty == 0 { commands.append("E\(basic)") }
    else { commands.append("ET\(basic),\(_pathNumber(transform.a)),\(_pathNumber(transform.b)),\(_pathNumber(transform.c)),\(_pathNumber(transform.d)),\(_pathNumber(transform.tx)),\(_pathNumber(transform.ty))") }
  }
  public mutating func addRoundedRect(
    in rect: CGRect,
    cornerSize: CGSize,
    style: RoundedCornerStyle = .circular,
    transform: CGAffineTransform = _swiftUIWebIdentityAffineTransform()
  ) {
    let basic = "\(_pathNumber(rect.origin.x)),\(_pathNumber(rect.origin.y)),\(_pathNumber(rect.size.width)),\(_pathNumber(rect.size.height)),\(_pathNumber(cornerSize.width)),\(_pathNumber(cornerSize.height)),\(style.rawValue)"
    if transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1 && transform.tx == 0 && transform.ty == 0 {
      commands.append("RR\(basic)")
    } else {
      commands.append("RRT\(basic),\(_pathNumber(transform.a)),\(_pathNumber(transform.b)),\(_pathNumber(transform.c)),\(_pathNumber(transform.d)),\(_pathNumber(transform.tx)),\(_pathNumber(transform.ty))")
    }
  }
  public mutating func addPath(_ path: Path, transform: CGAffineTransform = _swiftUIWebIdentityAffineTransform()) {
    let transformed = path.applying(transform)
    commands.append(contentsOf: transformed.commands)
    // `applying` is represented by a path-local transform marker. Reset it
    // after addPath so subsequent subpaths are not accidentally transformed.
    if transform.a != 1 || transform.b != 0 || transform.c != 0 || transform.d != 1 || transform.tx != 0 || transform.ty != 0 {
      commands.append("T1,0,0,1,0,0")
    }
  }
  public mutating func closeSubpath() { commands.append("Z") }

  /// Apple's `Path.addLines(_:)`: a move to the first point, then straight segments through the rest. The first point
  /// always starts a new subpath, even when the path has a current point, as SwiftUI documents.
  public mutating func addLines(_ lines: [CGPoint]) {
    guard let first = lines.first else { return }
    move(to: first)
    for point in lines.dropFirst() { addLine(to: point) }
  }

  /// Apple's `Path.addArc(tangent1End:tangent2End:radius:transform:)`: the arc of `radius` tangent to the segment from
  /// the current point to `tangent1End` and to the segment from there to `tangent2End`, as Canvas 2D's `arcTo` builds
  /// it. Degenerate input (a zero radius, or points that are collinear or repeated) adds a line to `tangent1End`. With no
  /// current point, or right after `closeSubpath()`, SwiftUI takes the origin as the start and begins a new subpath at the
  /// arc (or at `tangent1End` when degenerate) instead of drawing a line to it. The geometry is given in the path's space
  /// and `transform` places it.
  public mutating func addArc(
    tangent1End: CGPoint,
    tangent2End: CGPoint,
    radius: CGFloat,
    transform: CGAffineTransform = _swiftUIWebIdentityAffineTransform()
  ) {
    var local = Path()
    // A closed subpath leaves its start as the current point for lines, but not for this arc.
    let world = commands.last == "Z" ? nil : _pathCurrentPoint()
    // The current point is in the path's final space; the arc is computed in the space `transform` maps from.
    let start = world.map { _pathApply(transform.inverted(), $0) } ?? CGPoint(x: 0, y: 0)
    let opensSubpath = world == nil
    let v0 = (start.x - tangent1End.x, start.y - tangent1End.y)
    let v2 = (tangent2End.x - tangent1End.x, tangent2End.y - tangent1End.y)
    let length0 = (v0.0 * v0.0 + v0.1 * v0.1).squareRoot()
    let length2 = (v2.0 * v2.0 + v2.1 * v2.1).squareRoot()
    let u0 = (length0 > 0 ? v0.0 / length0 : 0, length0 > 0 ? v0.1 / length0 : 0)
    let u2 = (length2 > 0 ? v2.0 / length2 : 0, length2 > 0 ? v2.1 / length2 : 0)
    let cross = u0.0 * u2.1 - u0.1 * u2.0
    let dot = u0.0 * u2.0 + u0.1 * u2.1
    guard radius > 0, length0 > 0, length2 > 0, abs(cross) > 1e-12 else {
      if opensSubpath { local.move(to: tangent1End) } else { local.addLine(to: tangent1End) }
      addPath(local, transform: transform)
      return
    }
    // With alpha the angle at tangent1End, the tangent points lie at r / tan(alpha / 2) from it, and the center lies on
    // the bisector at r / sin(alpha / 2).
    let sinHalf = ((1 - dot) / 2).squareRoot()
    let cosHalf = ((1 + dot) / 2).squareRoot()
    let tangentDistance = radius * cosHalf / sinHalf
    let t1 = (tangent1End.x + u0.0 * tangentDistance, tangent1End.y + u0.1 * tangentDistance)
    let t2 = (tangent1End.x + u2.0 * tangentDistance, tangent1End.y + u2.1 * tangentDistance)
    let bisectorX = u0.0 + u2.0, bisectorY = u0.1 + u2.1
    let bisectorLength = (bisectorX * bisectorX + bisectorY * bisectorY).squareRoot()
    let centerDistance = radius / sinHalf
    let center = CGPoint(
      x: tangent1End.x + bisectorX / bisectorLength * centerDistance,
      y: tangent1End.y + bisectorY / bisectorLength * centerDistance
    )
    // The arc runs the short way between the two tangent points: its sweep is the signed angle between them.
    let r1 = (t1.0 - center.x, t1.1 - center.y), r2 = (t2.0 - center.x, t2.1 - center.y)
    let sweep = _tangentAtan2(r1.0 * r2.1 - r1.1 * r2.0, r1.0 * r2.0 + r1.1 * r2.1)
    let clockwise = sweep < 0
    let startAngle = _tangentAtan2(r1.1, r1.0)
    if opensSubpath { local.move(to: CGPoint(x: t1.0, y: t1.1)) } else { local.addLine(to: CGPoint(x: t1.0, y: t1.1)) }
    local.addArc(
      center: center, radius: radius,
      startAngle: Angle(radians: startAngle),
      endAngle: Angle(radians: startAngle + sweep),
      clockwise: clockwise
    )
    addPath(local, transform: transform)
  }

  /// Apple's `Path.contains(_:eoFill:)`: whether `point` is inside the path's fill, by its nonzero winding rule or,
  /// with `eoFill`, its even-odd rule. Curves are tested through their flattened polygons.
  public func contains(_ point: CGPoint, eoFill: Bool = false) -> Bool {
    var crossings = 0
    var winding = 0
    for subpath in _flattenPath(commands).subpaths where subpath.points.count >= 2 {
      // A fill closes every subpath, so the edge from the last point back to the first counts too.
      let points = subpath.points
      for index in points.indices {
        let a = points[index], b = points[(index + 1) % points.count]
        guard (a.y <= point.y) != (b.y <= point.y) else { continue }
        let x = a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y)
        if x > point.x {
          crossings += 1
          winding += b.y > a.y ? 1 : -1
        }
      }
    }
    return eoFill ? crossings % 2 == 1 : winding != 0
  }

  /// Apple's `Path.strokedPath(_:)`: the outline the stroke of `style` covers, as polygons with the same orientation
  /// (so the nonzero fill of the result is the stroke). Curves are flattened; dashes split the path before the outline.
  public func strokedPath(_ style: StrokeStyle) -> Path {
    var outline = Path()
    let half = style.lineWidth / 2
    guard half > 0, half.isFinite else { return outline }
    var pieces = _flattenPath(commands).subpaths
    // An odd-length pattern is repeated once to alternate on and off, as the canvas's setLineDash does: its cycle is twice the sum.
    let pattern = style.dash.count % 2 == 1 ? style.dash + style.dash : style.dash
    let period = pattern.reduce(0, +)
    if period > 0, pattern.allSatisfy({ $0 >= 0 && $0.isFinite }) {
      pieces = _dashedPieces(pieces, dash: pattern, phase: style.dashPhase, period: period)
    }
    for piece in pieces { _strokeOutline(piece, style: style, half: half, into: &outline) }
    return outline
  }

  public func applying(_ transform: CGAffineTransform) -> Path {
    guard transform.a != 1 || transform.b != 0 || transform.c != 0 || transform.d != 1 || transform.tx != 0 || transform.ty != 0 else { return self }
    var copy = self
    copy.commands.insert("T\(_pathNumber(transform.a)),\(_pathNumber(transform.b)),\(_pathNumber(transform.c)),\(_pathNumber(transform.d)),\(_pathNumber(transform.tx)),\(_pathNumber(transform.ty))", at: 0)
    return copy
  }

  public nonisolated func path(in rect: CGRect) -> Path { self }

  /// Renderer-facing SVG representation of this path.  The public `Path`
  /// model intentionally remains a compact, platform-neutral command stream;
  /// only the renderer SPI exposes the serialized geometry.  Keeping this
  /// conversion here means custom `Shape.path(in:)` implementations work in
  /// SVG-backed views without knowing anything about the browser.
  @_spi(Renderer) public var _svgPathData: String {
    _serializeSVGPathData(from: commands)
  }
}

// MARK: - Path geometry: flattening, current point and stroke outlines

/// The transform `T` markers of a path command stream set (`Path.applying`, `addPath`), applied to a point.
fileprivate struct _PathMatrix {
  var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0

  init() {}
  init(_ values: _PathNumbers, offset: Int = 0) {
    guard values.count >= offset + 6 else { return }
    a = values[offset]; b = values[offset + 1]; c = values[offset + 2]
    d = values[offset + 3]; tx = values[offset + 4]; ty = values[offset + 5]
  }
  func point(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: a * x + c * y + tx, y: b * x + d * y + ty)
  }
}

/// A subpath of a flattened path: its points in the path's final space, and whether it was closed.
fileprivate struct _FlatSubpath {
  var points: [CGPoint]
  var closed: Bool
}

/// Splits one raw command into its opcode and numbers. Mirrors the opcode rules `boundingRect` uses.
fileprivate func _pathOpcode(_ raw: String) -> (String, _PathNumbers) {
  let opcode: String
  if raw.hasPrefix("RRT") { opcode = "RRT" }
  else if raw.hasPrefix("RR") { opcode = "RR" }
  else if raw.hasPrefix("RT") { opcode = "RT" }
  else if raw.hasPrefix("ET") { opcode = "ET" }
  else { opcode = raw.first.map(String.init) ?? "" }
  return (opcode, _parsePathNumbers(raw.dropFirst(opcode.count)))
}

fileprivate func _pathApply(_ transform: CGAffineTransform, _ point: CGPoint) -> CGPoint {
  CGPoint(x: transform.a * point.x + transform.c * point.y + transform.tx, y: transform.b * point.x + transform.d * point.y + transform.ty)
}

/// The cosine and sine of an angle. `CGAffineTransform`'s rotation uses a longer series than the renderer's
/// `_swiftUIWebCos`/`_swiftUIWebSin`, which is accurate to about 1e-4 near a right angle.
fileprivate func _pathCosSin(_ angle: Double) -> (Double, Double) {
  let rotation = CGAffineTransform(rotationAngle: angle)
  return (rotation.a, rotation.b)
}

/// The angle of the vector (x, y), accurate to about 1e-9. The renderer's `_swiftUIWebAtan2` is an approximation
/// about 4e-3 off, which would move the tangent points of an arc.
fileprivate func _tangentAtan2(_ y: Double, _ x: Double) -> Double {
  let pi = Double.pi
  if x == 0 && y == 0 { return 0 }
  if x == 0 { return y > 0 ? pi / 2 : -pi / 2 }
  let ratio = y / x
  if x > 0 { return _tangentAtan(ratio) }
  return y >= 0 ? _tangentAtan(ratio) + pi : _tangentAtan(ratio) - pi
}

fileprivate func _tangentAtan(_ value: Double) -> Double {
  if value < 0 { return -_tangentAtan(-value) }
  if value > 1 { return Double.pi / 2 - _tangentAtan(1 / value) }
  // atan(x) = 2 atan(x / (1 + sqrt(1 + x^2))) brings the argument to at most 0.415, where the series converges fast.
  let reduced = value / (1 + (1 + value * value).squareRoot())
  let square = reduced * reduced
  var term = reduced, sum = 0.0
  for n in 0..<12 {
    sum += term / Double(2 * n + 1)
    term *= -square
  }
  return 2 * sum
}

/// Walks a path's commands and collects its subpaths as polylines in the final space. Curves and arcs become segments;
/// shapes become closed subpaths. `current` is the path's current point, which a following command continues from.
fileprivate struct _PathFlattener {
  var subpaths: [_FlatSubpath] = []
  var points: [CGPoint] = []
  var start: CGPoint?
  var current: CGPoint?

  mutating func flush(closed: Bool) {
    if !points.isEmpty { subpaths.append(_FlatSubpath(points: points, closed: closed)) }
    points = []
  }

  mutating func move(to point: CGPoint) {
    flush(closed: false)
    points = [point]
    start = point
    current = point
  }

  mutating func line(to point: CGPoint) {
    if points.isEmpty {
      // A segment after a closed subpath continues from its start, as a Path's current point does after `Z`.
      guard let current else { move(to: point); return }
      points = [current]
    }
    points.append(point)
    self.current = point
  }

  mutating func close() {
    guard !points.isEmpty else { return }
    flush(closed: true)
    current = start
  }

  /// Walks `commands` with `matrix` as the transform in effect. Returns the transform the walk ends with.
  mutating func run(_ commands: [String], matrix initial: _PathMatrix) -> _PathMatrix {
    var matrix = initial
    for raw in commands {
      let (opcode, v) = _pathOpcode(raw)
      switch opcode {
      case "T":
        if v.count >= 6 { matrix = _PathMatrix(v) }
      case "M":
        if v.count >= 2 { move(to: matrix.point(v[0], v[1])) }
      case "L":
        if v.count >= 2 { line(to: matrix.point(v[0], v[1])) }
      case "C":
        guard v.count >= 6 else { continue }
        let control1 = matrix.point(v[0], v[1]), control2 = matrix.point(v[2], v[3]), end = matrix.point(v[4], v[5])
        appendCurve(from: current ?? control1, control1, control2, end)
      case "Q":
        guard v.count >= 4 else { continue }
        let control = matrix.point(v[0], v[1]), end = matrix.point(v[2], v[3])
        appendQuad(from: current ?? control, control, end)
      case "A":
        guard v.count >= 6 else { continue }
        // The same arc convention the renderer serializes: `clockwise` runs the angle down from `start`.
        let radius = abs(v[2])
        let sweep = _boundedArcSweep(_directedArcSweep(start: v[3], end: v[4], clockwise: v[5] != 0))
        let steps = max(2, Int((sweep / (Double.pi / 16)).rounded(.up)))
        for index in 0...steps {
          let fraction = Double(index) / Double(steps)
          let angle = v[3] + (v[5] != 0 ? -1 : 1) * sweep * fraction
          let (cosine, sine) = _pathCosSin(angle)
          line(to: matrix.point(v[0] + radius * cosine, v[1] + radius * sine))
        }
      case "Z":
        close()
      case "R":
        _ = run(_rectCommands(v), matrix: matrix)
      case "RR":
        _ = run(_roundedRectCommands(v), matrix: matrix)
      case "E":
        _ = run(_ellipseCommands(v), matrix: matrix)
      // A shape with its own transform (`RT`, `ET`, `RRT`) uses that transform alone, as `boundingRect` does.
      case "RT":
        _ = run(_rectCommands(v), matrix: _PathMatrix(v, offset: 4))
      case "ET":
        _ = run(_ellipseCommands(v), matrix: _PathMatrix(v, offset: 4))
      case "RRT":
        _ = run(_roundedRectCommands(v), matrix: _PathMatrix(v, offset: 7))
      default:
        break
      }
    }
    return matrix
  }

  mutating func appendCurve(from p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) {
    let steps = 16
    if current == nil { move(to: p0) }
    for index in 1...steps {
      let t = Double(index) / Double(steps), s = 1 - t
      let x = s * s * s * p0.x + 3 * s * s * t * p1.x + 3 * s * t * t * p2.x + t * t * t * p3.x
      let y = s * s * s * p0.y + 3 * s * s * t * p1.y + 3 * s * t * t * p2.y + t * t * t * p3.y
      line(to: CGPoint(x: x, y: y))
    }
  }

  mutating func appendQuad(from p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint) {
    let steps = 12
    if current == nil { move(to: p0) }
    for index in 1...steps {
      let t = Double(index) / Double(steps), s = 1 - t
      line(to: CGPoint(x: s * s * p0.x + 2 * s * t * p1.x + t * t * p2.x, y: s * s * p0.y + 2 * s * t * p1.y + t * t * p2.y))
    }
  }
}

/// The commands of a rectangle `R` given its numbers `x, y, width, height`.
fileprivate func _rectCommands(_ v: _PathNumbers) -> [String] {
  guard v.count >= 4 else { return [] }
  let (x, y, w, h) = (v[0], v[1], v[2], v[3])
  return ["M\(x),\(y)", "L\(x + w),\(y)", "L\(x + w),\(y + h)", "L\(x),\(y + h)", "Z"]
}

/// The commands of an ellipse `E`: a 48-gon, which the stroke and containment tests can follow.
fileprivate func _ellipseCommands(_ v: _PathNumbers) -> [String] {
  guard v.count >= 4 else { return [] }
  let cx = v[0] + v[2] / 2, cy = v[1] + v[3] / 2, rx = abs(v[2] / 2), ry = abs(v[3] / 2)
  var commands: [String] = []
  for index in 0..<48 {
    let (cosine, sine) = _pathCosSin(2 * Double.pi * Double(index) / 48)
    commands.append((index == 0 ? "M" : "L") + "\(cx + rx * cosine),\(cy + ry * sine)")
  }
  commands.append("Z")
  return commands
}

/// The commands of a rounded rectangle `RR` (its corners are quadratic curves, as the renderer draws them).
fileprivate func _roundedRectCommands(_ v: _PathNumbers) -> [String] {
  guard v.count >= 6 else { return [] }
  let x = v[0], y = v[1], w = v[2], h = v[3]
  let rx = min(abs(v[4]), abs(w) / 2), ry = min(abs(v[5]), abs(h) / 2)
  return [
    "M\(x + rx),\(y)", "L\(x + w - rx),\(y)", "Q\(x + w),\(y),\(x + w),\(y + ry)",
    "L\(x + w),\(y + h - ry)", "Q\(x + w),\(y + h),\(x + w - rx),\(y + h)",
    "L\(x + rx),\(y + h)", "Q\(x),\(y + h),\(x),\(y + h - ry)",
    "L\(x),\(y + ry)", "Q\(x),\(y),\(x + rx),\(y)", "Z"
  ]
}

/// How far an arc runs from `start` to `end` going the way `clockwise` says (the angle falls when it is clockwise): a sweep
/// that would run the other way is the rest of the circle, so the arc ends at the requested angle whatever the direction. A
/// whole turn, which the stored thousandth precision may leave a little short, stays a whole turn.
func _directedArcSweep(start: Double, end: Double, clockwise: Bool) -> Double {
  let raw = clockwise ? start - end : end - start
  if raw >= 0 { return raw }
  let turn = 6.283185307179586
  if -raw >= turn - 0.001 { return -raw }
  return raw + turn * (1 + (-raw / turn).rounded(.down))
}

/// A sweep of more than two turns as the one to two turns that end at the same angle: what is drawn is the same, and the
/// points a sweep from data (5e8 radians) would take are past a 32-bit Int's range in the browser build.
func _boundedArcSweep(_ sweep: Double) -> Double {
  let turn = 6.283185307179586
  guard sweep.isFinite else { return 0 }
  return sweep > 2 * turn ? turn + sweep.truncatingRemainder(dividingBy: turn) : sweep
}

/// The subpaths of `commands` in the path's final space.
fileprivate func _flattenPath(_ commands: [String]) -> _PathFlattener {
  var flattener = _PathFlattener()
  _ = flattener.run(commands, matrix: _PathMatrix())
  flattener.flush(closed: false)
  return flattener
}

extension Path {
  /// The point the next command continues from, in the space the path's commands are written in, or nil when no
  /// subpath is open.
  fileprivate func _pathCurrentPoint() -> CGPoint? {
    _flattenPath(commands).current
  }
}

/// The subpaths of `pieces` cut into the dashes of `dash`, which start `phase` into the pattern. Dashes are open.
fileprivate func _dashedPieces(_ pieces: [_FlatSubpath], dash: [Double], phase: Double, period: Double) -> [_FlatSubpath] {
  var result: [_FlatSubpath] = []
  // Dashes far shorter than the path (a dash of 1 on a line of 1e9, or 1e-300 that never advances) would take billions
  // of turns: past this many the rest of the path is drawn undashed.
  var turns = 0
  let turnLimit = 100_000
  for piece in pieces {
    var points = piece.points
    if piece.closed, let first = points.first { points.append(first) }
    guard points.count >= 2 else { continue }
    // Advance the pattern to the phase; `index` is the dash in effect and `remaining` its length left.
    var index = 0
    var remaining = dash[0]
    var offset = phase.truncatingRemainder(dividingBy: period)
    if offset < 0 { offset += period }
    while offset > 0 {
      if offset >= remaining {
        offset -= remaining
        index = (index + 1) % dash.count
        remaining = dash[index]
      } else {
        remaining -= offset
        offset = 0
      }
    }
    var on = index % 2 == 0
    let startedOn = on
    var toggled = false
    var local: [_FlatSubpath] = []
    var current: [CGPoint] = on ? [points[0]] : []
    for segment in 0..<(points.count - 1) {
      let a = points[segment], b = points[segment + 1]
      let length = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
      var travelled = 0.0
      while length - travelled > remaining, turns < turnLimit {
        turns += 1
        travelled += remaining
        let fraction = length > 0 ? travelled / length : 0
        let point = CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
        if on {
          current.append(point)
          local.append(_FlatSubpath(points: current, closed: false))
          current = []
        } else {
          current = [point]
        }
        on.toggle()
        toggled = true
        index = (index + 1) % dash.count
        remaining = dash[index]
      }
      remaining -= length - travelled
      if on { current.append(b) }
    }
    if on, current.count >= 1 { local.append(_FlatSubpath(points: current, closed: false)) }
    // A dash on at both ends of a closed contour covers its seam: a dash over the whole contour is the closed contour, and
    // the last dash and the first are one dash that turns the corner there, not two with a butt cap each.
    if piece.closed, startedOn, on, !local.isEmpty {
      if !toggled {
        local = [_FlatSubpath(points: piece.points, closed: true)]
      } else if local.count >= 2, let first = local.first, let last = local.last {
        local.removeFirst()
        local.removeLast()
        local.append(_FlatSubpath(points: last.points + first.points.dropFirst(), closed: false))
      }
    }
    result += local
  }
  return result
}

/// Adds `points` to `path` as a closed polygon, wound counter-clockwise, so that overlapping polygons of one stroke
/// add up under the nonzero rule instead of cancelling.
fileprivate func _addPolygon(_ points: [CGPoint], to path: inout Path) {
  guard points.count >= 3 else { return }
  var area = 0.0
  for index in points.indices {
    let a = points[index], b = points[(index + 1) % points.count]
    area += a.x * b.y - b.x * a.y
  }
  let ordered = area < 0 ? Array(points.reversed()) : points
  path.move(to: ordered[0])
  for point in ordered.dropFirst() { path.addLine(to: point) }
  path.closeSubpath()
}

/// A circle of `radius` about `center`, as a polygon for round joins and caps.
fileprivate func _circlePolygon(center: CGPoint, radius: Double) -> [CGPoint] {
  (0..<32).map { index in
    let (cosine, sine) = _pathCosSin(2 * Double.pi * Double(index) / 32)
    return CGPoint(x: center.x + radius * cosine, y: center.y + radius * sine)
  }
}

/// The outline of one polyline (open, or closed when `piece.closed`) stroked with `style`, of half-width `half`: a quad
/// per segment, a join at each interior vertex, and a cap at each end of an open polyline.
fileprivate func _strokeOutline(_ piece: _FlatSubpath, style: StrokeStyle, half: Double, into outline: inout Path) {
  // Repeated points give no direction, so they are dropped; a closed polyline's last point repeats its first.
  var points: [CGPoint] = []
  for point in piece.points {
    if let last = points.last, abs(last.x - point.x) <= 1e-9, abs(last.y - point.y) <= 1e-9 { continue }
    points.append(point)
  }
  if piece.closed, points.count > 1, let first = points.first, let last = points.last,
     abs(first.x - last.x) <= 1e-9, abs(first.y - last.y) <= 1e-9 {
    points.removeLast()
  }
  if points.count == 1 {
    // A zero-length dash or subpath is a dot only with round caps; a square cap has no direction to face.
    if style.lineCap == .round { _addPolygon(_circlePolygon(center: points[0], radius: half), to: &outline) }
    return
  }
  guard points.count >= 2 else { return }
  let count = points.count
  let closed = piece.closed
  // Unit direction and left normal of each segment, in order.
  let segmentCount = closed ? count : count - 1
  var directions: [CGPoint] = []
  for segment in 0..<segmentCount {
    let a = points[segment], b = points[(segment + 1) % count]
    let dx = b.x - a.x, dy = b.y - a.y
    let length = (dx * dx + dy * dy).squareRoot()
    directions.append(CGPoint(x: dx / length, y: dy / length))
  }
  for segment in 0..<segmentCount {
    let a = points[segment], b = points[(segment + 1) % count], d = directions[segment]
    let normal = CGPoint(x: -d.y * half, y: d.x * half)
    _addPolygon([
      CGPoint(x: a.x + normal.x, y: a.y + normal.y), CGPoint(x: b.x + normal.x, y: b.y + normal.y),
      CGPoint(x: b.x - normal.x, y: b.y - normal.y), CGPoint(x: a.x - normal.x, y: a.y - normal.y)
    ], to: &outline)
  }
  // Joins: at every vertex of a closed polyline, else at its interior vertices.
  let joinVertices = closed ? Array(0..<count) : Array(1..<(count - 1))
  for vertex in joinVertices {
    let incoming = directions[(vertex - 1 + segmentCount) % segmentCount]
    let outgoing = directions[vertex % segmentCount]
    let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
    let dot = incoming.x * outgoing.x + incoming.y * outgoing.y
    if abs(cross) < 1e-12 && dot > 0 { continue }
    let center = points[vertex]
    if style.lineJoin == .round {
      _addPolygon(_circlePolygon(center: center, radius: half), to: &outline)
      continue
    }
    // The outer side of the turn: the right side of a left turn, and the reverse.
    let side = cross > 0 ? -1.0 : 1.0
    let o0 = CGPoint(x: -incoming.y * half * side, y: incoming.x * half * side)
    let o1 = CGPoint(x: -outgoing.y * half * side, y: outgoing.x * half * side)
    let tip = CGPoint(x: o0.x + o1.x, y: o0.y + o1.y)
    let tipLength = (tip.x * tip.x + tip.y * tip.y).squareRoot()
    // The miter reaches h / cos(phi) from the vertex, where phi is half the angle between the two offsets. Past the
    // miter limit it is beveled.
    let cosine = tipLength > 0 ? (tip.x * o0.x + tip.y * o0.y) / tipLength / half : 0
    let mitered = style.lineJoin == .miter && cosine > 1e-12 && 1 / cosine <= style.miterLimit
    if mitered {
      let distance = half / cosine
      let apex = CGPoint(x: center.x + tip.x / tipLength * distance, y: center.y + tip.y / tipLength * distance)
      _addPolygon([center, CGPoint(x: center.x + o0.x, y: center.y + o0.y), apex, CGPoint(x: center.x + o1.x, y: center.y + o1.y)], to: &outline)
    } else {
      _addPolygon([center, CGPoint(x: center.x + o0.x, y: center.y + o0.y), CGPoint(x: center.x + o1.x, y: center.y + o1.y)], to: &outline)
    }
  }
  guard !closed else { return }
  // Caps face outward from each end: butt adds nothing, square extends the end by the half-width, and round adds a
  // circle, which covers the half disc that sticks out.
  let ends: [(CGPoint, CGPoint)] = [
    (points[0], CGPoint(x: -directions[0].x, y: -directions[0].y)),
    (points[count - 1], directions[segmentCount - 1])
  ]
  for (point, direction) in ends {
    switch style.lineCap {
    case .round:
      _addPolygon(_circlePolygon(center: point, radius: half), to: &outline)
    case .square:
      let normal = CGPoint(x: -direction.y * half, y: direction.x * half)
      let ahead = CGPoint(x: direction.x * half, y: direction.y * half)
      _addPolygon([
        CGPoint(x: point.x + normal.x, y: point.y + normal.y), CGPoint(x: point.x + normal.x + ahead.x, y: point.y + normal.y + ahead.y),
        CGPoint(x: point.x - normal.x + ahead.x, y: point.y - normal.y + ahead.y), CGPoint(x: point.x - normal.x, y: point.y - normal.y)
      ], to: &outline)
    default:
      break
    }
  }
}

public extension Shape {
  /// Custom shapes may implement SwiftUI's familiar `path(in:)` method.  A
  /// default keeps older SwiftUIWeb shapes source-compatible while allowing
  /// Canvas to consume real custom geometry when supplied.
  nonisolated func path(in rect: CGRect) -> Path { Path() }
}

@inline(__always)
private func _unsignedDecimal(_ value: UInt64) -> String {
  var remaining = value
  var storage: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
    (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  return withUnsafeMutableBytes(of: &storage) { raw in
    var start = raw.count
    repeat {
      start -= 1
      raw[start] = UInt8(remaining % 10) + 48
      remaining /= 10
    } while remaining != 0
    let bytes = UnsafeBufferPointer(
      start: raw.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: start),
      count: raw.count - start
    )
    return String(decoding: bytes, as: UTF8.self)
  }
}

@inline(__always)
internal func _pathNumber<T: BinaryFloatingPoint>(_ value: T) -> String {
  let value = Double(value)
  guard value.isFinite else { return "0" }
  let scaledValue = (value * 1000).rounded()
  guard scaledValue >= Double(Int64.min), scaledValue < Double(Int64.max) else { return "0" }
  let scaled = Int64(scaledValue)
  let sign = scaled < 0 ? "-" : ""
  let magnitude = scaled.magnitude
  let whole = magnitude / 1000
  let fractionalMagnitude = magnitude % 1000
  guard fractionalMagnitude != 0 else { return sign + _unsignedDecimal(whole) }
  var digits = _unsignedDecimal(fractionalMagnitude)
  while digits.count < 3 { digits = "0" + digits }
  while digits.last == "0" { digits.removeLast() }
  return sign + _unsignedDecimal(whole) + "." + digits
}

/// Arc angles, in radians, need more precision than coordinates: a thousandth of a radian moves the end of an arc by a
/// thousandth of its radius, so a quarter turn of radius 10 would end 0.002 off the axis.
internal func _pathAngleNumber(_ value: Double) -> String { _rampNumber(value) }

/// Gradient stop offsets need more precision than path coordinates. A repeated
/// ramp places several stops within a few thousandths of each other, so the
/// three-decimal `_pathNumber` would collapse them onto one offset.
internal func _rampNumber(_ value: Double) -> String {
  guard value.isFinite else { return "0" }
  let scaledValue = (value * 1_000_000).rounded()
  guard abs(scaledValue) < 9.0e15 else { return "0" }
  let scaled = Int64(scaledValue)
  let sign = scaled < 0 ? "-" : ""
  let magnitude = scaled.magnitude
  let whole = magnitude / 1_000_000
  let fractionalMagnitude = magnitude % 1_000_000
  guard fractionalMagnitude != 0 else { return sign + _unsignedDecimal(whole) }
  var digits = _unsignedDecimal(fractionalMagnitude)
  while digits.count < 6 { digits = "0" + digits }
  while digits.last == "0" { digits.removeLast() }
  return sign + _unsignedDecimal(whole) + "." + digits
}

/// A fixed-capacity parse result for Path's compact comma-separated commands.
/// Avoid `String.split(...).map(...)` here: it creates two transient arrays for
/// every Shape path and can exhaust or corrupt the small Embedded WASM heap on
/// large SwiftUI canvases.
private struct _PathNumbers {
  private var v0 = 0.0, v1 = 0.0, v2 = 0.0, v3 = 0.0, v4 = 0.0
  private var v5 = 0.0, v6 = 0.0, v7 = 0.0, v8 = 0.0, v9 = 0.0
  private var v10 = 0.0, v11 = 0.0, v12 = 0.0
  private(set) var count = 0

  mutating func append(_ value: Double) {
    switch count {
    case 0: v0 = value
    case 1: v1 = value
    case 2: v2 = value
    case 3: v3 = value
    case 4: v4 = value
    case 5: v5 = value
    case 6: v6 = value
    case 7: v7 = value
    case 8: v8 = value
    case 9: v9 = value
    case 10: v10 = value
    case 11: v11 = value
    default: v12 = value
    }
    count += 1
  }

  subscript(index: Int) -> Double {
    switch index {
    case 0: v0
    case 1: v1
    case 2: v2
    case 3: v3
    case 4: v4
    case 5: v5
    case 6: v6
    case 7: v7
    case 8: v8
    case 9: v9
    case 10: v10
    case 11: v11
    default: v12
    }
  }
}

private func _parsePathNumbers(_ payload: Substring) -> _PathNumbers {
  var values = _PathNumbers()
  var start = payload.startIndex
  while true {
    let end = payload[start...].firstIndex(of: ",") ?? payload.endIndex
    values.append(Double(payload[start..<end]) ?? 0)
    if end == payload.endIndex { break }
    start = payload.index(after: end)
  }
  return values
}

// MARK: - SVG path serialization

/// Convert the internal command stream to SVG path data.  Canvas commands use
/// center/radius arcs and explicit rectangle/ellipse opcodes, while SVG uses
/// endpoint arcs.  The conversion deliberately samples only transformed
/// ellipses/arcs; the common identity path remains a compact native SVG path.
private func _serializeSVGPathData(from commands: [String]) -> String {
  let tau = Double.pi * 2
  struct Matrix {
    var a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0
    func point(_ x: Double, _ y: Double) -> (Double, Double) {
      (a * x + c * y + tx, b * x + d * y + ty)
    }
  }
  func transformed(_ point: (Double, Double), by matrix: Matrix) -> String {
    let result = matrix.point(point.0, point.1)
    return "\(_pathNumber(result.0)) \(_pathNumber(result.1))"
  }
  func matrix(_ values: _PathNumbers, offset: Int = 0) -> Matrix {
    guard values.count >= offset + 6 else { return Matrix() }
    return Matrix(a: values[offset], b: values[offset + 1], c: values[offset + 2], d: values[offset + 3], tx: values[offset + 4], ty: values[offset + 5])
  }
  func append(_ fragment: String, to output: inout String) {
    if !output.isEmpty { output.append(" ") }
    output.append(contentsOf: fragment)
  }
  func appendEllipse(_ x: Double, _ y: Double, _ width: Double, _ height: Double, by transform: Matrix, into output: inout String) {
    let cx = x + width / 2
    let cy = y + height / 2
    let rx = abs(width / 2)
    let ry = abs(height / 2)
    let identity = transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1 && transform.tx == 0 && transform.ty == 0
    if identity {
      // Like Core Graphics/SwiftUI, an ellipse starts at its trailing
      // midpoint (angle 0) and runs clockwise on screen. `trim(from:to:)`
      // depends on this: `Circle().trim(from: 0, to: 0.25)` spans 3 to 6 o'clock.
      append("M \(transformed((cx + rx, cy), by: transform))", to: &output)
      append("A \(_pathNumber(rx)) \(_pathNumber(ry)) 0 1 1 \(transformed((cx - rx, cy), by: transform))", to: &output)
      append("A \(_pathNumber(rx)) \(_pathNumber(ry)) 0 1 1 \(transformed((cx + rx, cy), by: transform))", to: &output)
      append("Z", to: &output)
      return
    }
    let samples = 32
    for index in 0...samples {
      let angle = tau * Double(index) / Double(samples)
      let point = transformed((cx + _swiftUIWebCos(angle) * rx, cy + _swiftUIWebSin(angle) * ry), by: transform)
      append(index == 0 ? "M \(point)" : "L \(point)", to: &output)
    }
    append("Z", to: &output)
  }
  func appendRoundedRect(_ values: _PathNumbers, by transform: Matrix, into output: inout String) {
    guard values.count >= 6 else { return }
    let x = values[0], y = values[1], width = values[2], height = values[3]
    let rx = min(abs(values[4]), abs(width) / 2)
    let ry = min(abs(values[5]), abs(height) / 2)
    let topLeft = (x + rx, y)
    let topRight = (x + width - rx, y)
    let rightTop = (x + width, y + ry)
    let rightBottom = (x + width, y + height - ry)
    let bottomRight = (x + width - rx, y + height)
    let bottomLeft = (x + rx, y + height)
    let leftBottom = (x, y + height - ry)
    let leftTop = (x, y + ry)
    append("M \(transformed(topLeft, by: transform))", to: &output)
    append("L \(transformed(topRight, by: transform))", to: &output)
    append("Q \(transformed((x + width, y), by: transform)) \(transformed(rightTop, by: transform))", to: &output)
    append("L \(transformed(rightBottom, by: transform))", to: &output)
    append("Q \(transformed((x + width, y + height), by: transform)) \(transformed(bottomRight, by: transform))", to: &output)
    append("L \(transformed(bottomLeft, by: transform))", to: &output)
    append("Q \(transformed((x, y + height), by: transform)) \(transformed(leftBottom, by: transform))", to: &output)
    append("L \(transformed(leftTop, by: transform))", to: &output)
    append("Q \(transformed((x, y), by: transform)) \(transformed(topLeft, by: transform))", to: &output)
    append("Z", to: &output)
  }
  func appendRect(_ values: _PathNumbers, by transform: Matrix, into output: inout String) {
    guard values.count >= 4 else { return }
    let x = values[0], y = values[1], width = values[2], height = values[3]
    append("M \(transformed((x, y), by: transform))", to: &output)
    append("L \(transformed((x + width, y), by: transform))", to: &output)
    append("L \(transformed((x + width, y + height), by: transform))", to: &output)
    append("L \(transformed((x, y + height), by: transform))", to: &output)
    append("Z", to: &output)
  }

  var output = ""
  var transform = Matrix()
  for raw in commands {
    let opcode: String
    if raw.hasPrefix("RRT") { opcode = "RRT" }
    else if raw.hasPrefix("RR") { opcode = "RR" }
    else if raw.hasPrefix("RT") { opcode = "RT" }
    else if raw.hasPrefix("ET") { opcode = "ET" }
    else { opcode = raw.first.map(String.init) ?? "" }
    let values = _parsePathNumbers(raw.dropFirst(opcode.count))
    switch opcode {
    case "M":
      if values.count >= 2 { append("M \(transformed((values[0], values[1]), by: transform))", to: &output) }
    case "L":
      if values.count >= 2 { append("L \(transformed((values[0], values[1]), by: transform))", to: &output) }
    case "C":
      if values.count >= 6 {
        append("C \(transformed((values[0], values[1]), by: transform)) \(transformed((values[2], values[3]), by: transform)) \(transformed((values[4], values[5]), by: transform))", to: &output)
      }
    case "Q":
      if values.count >= 4 { append("Q \(transformed((values[0], values[1]), by: transform)) \(transformed((values[2], values[3]), by: transform))", to: &output) }
    case "A":
      guard values.count >= 6 else { continue }
      let cx = values[0], cy = values[1], radius = abs(values[2])
      let start = values[3], end = values[4], clockwise = values[5] != 0
      let magnitude = _directedArcSweep(start: start, end: end, clockwise: clockwise)
      let startPoint = (cx + radius * _swiftUIWebCos(start), cy + radius * _swiftUIWebSin(start))
      let endPoint = (cx + radius * _swiftUIWebCos(end), cy + radius * _swiftUIWebSin(end))
      let identity = transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1 && transform.tx == 0 && transform.ty == 0
      if identity {
        // Arc commands are stored at thousandth precision. Allow one unit of
        // that quantization when recognizing a complete revolution so a
        // 360-degree angle does not fall through to SVG's single-arc path
        // (which cannot represent a full circle with coincident endpoints).
        if magnitude >= tau - 0.001 {
          let middleAngle = start + (clockwise ? -Double.pi : Double.pi)
          let middle = (cx + radius * _swiftUIWebCos(middleAngle), cy + radius * _swiftUIWebSin(middleAngle))
          append("M \(transformed(startPoint, by: transform))", to: &output)
          append("A \(_pathNumber(radius)) \(_pathNumber(radius)) 0 1 \(clockwise ? 0 : 1) \(transformed(middle, by: transform))", to: &output)
          append("A \(_pathNumber(radius)) \(_pathNumber(radius)) 0 1 \(clockwise ? 0 : 1) \(transformed(startPoint, by: transform))", to: &output)
        } else {
          if output.isEmpty { append("M \(transformed(startPoint, by: transform))", to: &output) }
          append("A \(_pathNumber(radius)) \(_pathNumber(radius)) 0 \(magnitude > Double.pi ? 1 : 0) \(clockwise ? 0 : 1) \(transformed(endPoint, by: transform))", to: &output)
        }
      } else {
        let magnitude = _boundedArcSweep(magnitude)
        let steps = max(2, Int((magnitude / (Double.pi / 12)).rounded(.up)))
        for index in 0...steps {
          let fraction = Double(index) / Double(steps)
          let angle = start + (clockwise ? -1 : 1) * magnitude * fraction
          let point = transformed((cx + radius * _swiftUIWebCos(angle), cy + radius * _swiftUIWebSin(angle)), by: transform)
          append(index == 0 && output.isEmpty ? "M \(point)" : "L \(point)", to: &output)
        }
      }
    case "R":
      appendRect(values, by: transform, into: &output)
    case "E":
      if values.count >= 4 { appendEllipse(values[0], values[1], values[2], values[3], by: transform, into: &output) }
    case "RR":
      appendRoundedRect(values, by: transform, into: &output)
    case "T":
      if values.count >= 6 { transform = matrix(values) }
    case "RT":
      if values.count >= 10 { appendRect(values, by: matrix(values, offset: 4), into: &output) }
    case "ET":
      if values.count >= 10 { appendEllipse(values[0], values[1], values[2], values[3], by: matrix(values, offset: 4), into: &output) }
    case "RRT":
      if values.count >= 13 { appendRoundedRect(values, by: matrix(values, offset: 7), into: &output) }
    case "Z": append("Z", to: &output)
    default: break
    }
  }
  return output
}

// Small deterministic trig helpers keep SVG serialization available to the
// Foundation-free WASM build as well as native hosts. The approximation is
// more than sufficient for direction/geometry serialization and avoids a
// platform-specific libm dependency in the Swift-facing core.
private func _svgReducedAngle(_ value: Double) -> Double {
  let tau = 6.283185307179586
  guard value.isFinite else { return 0 }
  // The IEEE remainder is in [-pi, pi] at once; subtracting a turn at a time never ends for an angle of 1e17 radians.
  return value.remainder(dividingBy: tau)
}

internal func _swiftUIWebSin(_ value: Double) -> Double {
  let angle = _svgReducedAngle(value)
  let square = angle * angle
  return angle * (1 - square / 6 + square * square / 120 - square * square * square / 5_040)
}

internal func _swiftUIWebCos(_ value: Double) -> Double {
  let angle = _svgReducedAngle(value)
  let square = angle * angle
  return 1 - square / 2 + square * square / 24 - square * square * square / 720
}

@inline(__always)
internal func _swiftUIWebAtan2(_ y: Double, _ x: Double) -> Double {
  let pi = 3.141592653589793
  guard x != 0 else { return y >= 0 ? pi / 2 : -pi / 2 }
  let z = y / x
  let approximation = z / (1 + 0.28 * z * z)
  if x > 0 { return approximation }
  return y >= 0 ? approximation + pi : approximation - pi
}

/// A browser-neutral representation of SwiftUI's two-dimensional gradient
/// mesh.  The public surface intentionally contains only SwiftUI-shaped
/// values; the browser adapter consumes the compact payload emitted by
/// `_render` and rasterizes it into a retained Canvas 2D element.
public nonisolated struct MeshGradient: ShapeStyle, Hashable, Sendable {
  public typealias Body = Never

  /// SwiftUI keeps unresolved and already-resolved color arrays in a small
  /// enum so renderer implementations can avoid resolving colors twice.
  /// Array-literal support is an additive convenience for the common
  /// colors: [.red, .blue] spelling with the Locations initializer.
  public enum Colors: Hashable, Sendable {
    case colors([Color])
    case resolvedColors([Color.Resolved])

    /// Resolved view of either case, used by the renderer and tests.
    package var _values: [Color] {
      switch self {
      case .colors(let colors): return colors
      case .resolvedColors(let colors): return colors.map { $0.color }
      }
    }
  }

  public struct BezierPoint: Hashable, Sendable {
    public var position: SIMD2<Float>
    public var leadingControlPoint: SIMD2<Float>
    public var topControlPoint: SIMD2<Float>
    public var trailingControlPoint: SIMD2<Float>
    public var bottomControlPoint: SIMD2<Float>

    public init(
      position: SIMD2<Float>,
      leadingControlPoint: SIMD2<Float>,
      topControlPoint: SIMD2<Float>,
      trailingControlPoint: SIMD2<Float>,
      bottomControlPoint: SIMD2<Float>
    ) {
      self.position = position
      self.leadingControlPoint = leadingControlPoint
      self.topControlPoint = topControlPoint
      self.trailingControlPoint = trailingControlPoint
      self.bottomControlPoint = bottomControlPoint
    }
  }

  public enum Locations: Hashable, Sendable {
    case points([SIMD2<Float>])
    case bezierPoints([BezierPoint])
  }

  public let width: Int
  public let height: Int
  public let locations: Locations
  public let colors: Colors
  public let background: Color
  public let smoothsColors: Bool
  public let colorSpace: Gradient.ColorSpace

  /// Convenience accessors used by the original SwiftUI points initializer.
  /// `locations` remains the authoritative value so explicit Bezier control
  /// points survive round-tripping through the public API.
  package var points: [SIMD2<Float>] {
    switch locations {
    case .points(let points): return points
    case .bezierPoints(let points): return points.map { $0.position }
    }
  }

  public nonisolated init(
    width: Int,
    height: Int,
    points: [SIMD2<Float>],
    colors: [Color],
    background: Color = .clear,
    smoothsColors: Bool = true,
    colorSpace: Gradient.ColorSpace = .device
  ) {
    self.width = max(1, width)
    self.height = max(1, height)
    locations = .points(points)
    self.colors = .colors(colors)
    self.background = background
    self.smoothsColors = smoothsColors
    self.colorSpace = colorSpace
  }

  public nonisolated init(
    width: Int,
    height: Int,
    locations: MeshGradient.Locations,
    colors: MeshGradient.Colors,
    background: Color = .clear,
    smoothsColors: Bool = true,
    colorSpace: Gradient.ColorSpace = .device
  ) {
    self.width = max(1, width)
    self.height = max(1, height)
    self.locations = locations
    self.colors = colors
    self.background = background
    self.smoothsColors = smoothsColors
    self.colorSpace = colorSpace
  }

  public nonisolated init(
    width: Int,
    height: Int,
    bezierPoints: [MeshGradient.BezierPoint],
    colors: [Color],
    background: Color = .clear,
    smoothsColors: Bool = true,
    colorSpace: Gradient.ColorSpace = .device
  ) {
    self.init(width: width, height: height, locations: .bezierPoints(bezierPoints), colors: .colors(colors), background: background, smoothsColors: smoothsColors, colorSpace: colorSpace)
  }

  public nonisolated init(
    width: Int,
    height: Int,
    points: [SIMD2<Float>],
    resolvedColors: [Color.Resolved],
    background: Color = .clear,
    smoothsColors: Bool = true,
    colorSpace: Gradient.ColorSpace = .device
  ) {
    self.init(width: width, height: height, points: points, colors: resolvedColors.map { $0.color }, background: background, smoothsColors: smoothsColors, colorSpace: colorSpace)
  }

  public nonisolated init(
    width: Int,
    height: Int,
    bezierPoints: [MeshGradient.BezierPoint],
    resolvedColors: [Color.Resolved],
    background: Color = .clear,
    smoothsColors: Bool = true,
    colorSpace: Gradient.ColorSpace = .device
  ) {
    self.init(width: width, height: height, bezierPoints: bezierPoints, colors: resolvedColors.map { $0.color }, background: background, smoothsColors: smoothsColors, colorSpace: colorSpace)
  }

  /// CSS is retained as a static/WASI fallback and for hosts that do not load
  /// the optional mesh rasterizer. Browser hosts replace the pixels in the
  /// same canvas without changing this semantic fallback.
  public var _swiftUIWebCSSValue: String {
    let stops = colors._values.prefix(6).map { $0.cssValue }
    let values = stops.isEmpty ? [background.cssValue] : stops
    return "linear-gradient(135deg, \(values.joined(separator: ", ")))"
  }

  public func _render(in context: _RenderContext) -> _RenderNode {
    let proposal = context._layoutProposal
    let width = proposal?.width?.isFinite == true ? max(0, Double(proposal!.width!)) : 300
    let height = proposal?.height?.isFinite == true ? max(0, Double(proposal!.height!)) : 150
    let node = _RenderNode.element("canvas")
    node.classes = ["mesh-gradient"]
    node.attributes["data-mesh-gradient"] = "true"
    node.attributes["data-mesh-gradient-width"] = String(_meshWidth)
    node.attributes["data-mesh-gradient-height"] = String(_meshHeight)
    node.attributes["data-mesh-gradient-smooths-colors"] = smoothsColors ? "true" : "false"
    node.attributes["data-mesh-gradient-color-space"] = colorSpace.rawValue
    node.attributes["data-mesh-gradient-size"] = "\(_pathNumber(width)),\(_pathNumber(height))"
    node.attributes["data-mesh-gradient-fingerprint"] = _meshGradientFingerprint(self)
    node.attributes["data-mesh-gradient-payload"] = _meshGradientPayload(self)
    node.styles["display"] = "block"
    node.styles["background"] = _swiftUIWebCSSValue
    if let proposed = proposal?.width, proposed.isFinite { node.styles["width"] = "\(_pathNumber(Double(proposed)))px" }
    if let proposed = proposal?.height, proposed.isFinite { node.styles["height"] = "\(_pathNumber(Double(proposed)))px" }
    return node
  }
}

private func _meshFinite(_ value: Float, fallback: Float = 0) -> Float {
  value.isFinite ? value : fallback
}

extension MeshGradient {
  /// The grid the page draws: at most 64 by 64 points. A size from data (50 000 by 50 000) would overflow width × height
  /// where Int is 32 bits, or ask for gigabytes of points.
  fileprivate var _meshWidth: Int { min(max(width, 1), 64) }
  fileprivate var _meshHeight: Int { min(max(height, 1), 64) }
}

private func _meshPoints(_ mesh: MeshGradient) -> [SIMD2<Float>] {
  let expected = mesh._meshWidth * mesh._meshHeight
  let source = mesh.points
  var points: [SIMD2<Float>] = []
  points.reserveCapacity(expected)
  for index in 0..<expected {
    if index < source.count {
      let point = source[index]
      points.append(SIMD2<Float>(_meshFinite(point[0]), _meshFinite(point[1])))
    } else {
      let column = mesh._meshWidth > 1 ? index % mesh._meshWidth : 0
      let row = index / mesh._meshWidth
      let x = mesh._meshWidth > 1 ? Float(column) / Float(mesh._meshWidth - 1) : 0
      let y = mesh._meshHeight > 1 ? Float(row) / Float(mesh._meshHeight - 1) : 0
      points.append(SIMD2<Float>(x, y))
    }
  }
  return points
}

private func _meshColors(_ mesh: MeshGradient) -> [Color] {
  let expected = mesh._meshWidth * mesh._meshHeight
  var colors = mesh.colors._values
  if colors.count < expected { colors.append(contentsOf: repeatElement(mesh.background, count: expected - colors.count)) }
  if colors.count > expected { colors.removeLast(colors.count - expected) }
  return colors
}

private func _meshJSONString(_ value: String) -> String {
  // Per Unicode scalar, as AVFoundation's `_jsonString`: every control character is escaped, not only the named ones.
  var out = "\""
  for scalar in value.unicodeScalars {
    switch scalar {
    case "\"": out += "\\\""
    case "\\": out += "\\\\"
    case "\u{08}": out += "\\b"
    case "\u{0C}": out += "\\f"
    case "\n": out += "\\n"
    case "\r": out += "\\r"
    case "\t": out += "\\t"
    default:
      if scalar.value < 0x20 {
        let digits = Array("0123456789abcdef")
        out += "\\u00" + String(digits[Int(scalar.value >> 4)]) + String(digits[Int(scalar.value & 15)])
      } else {
        out.unicodeScalars.append(scalar)
      }
    }
  }
  return out + "\""
}

private func _meshNumber(_ value: Float) -> String {
  _pathNumber(_meshFinite(value))
}

private func _meshGradientPayload(_ mesh: MeshGradient) -> String {
  let points = _meshPoints(mesh).map { "[\(_meshNumber($0[0])),\(_meshNumber($0[1]))]" }.joined(separator: ",")
  let colors = _meshColors(mesh).map { _meshJSONString($0.cssValue) }.joined(separator: ",")
  let bezierPoints: String
  switch mesh.locations {
  case .points:
    bezierPoints = "null"
  case .bezierPoints(let source):
    let expected = mesh._meshWidth * mesh._meshHeight
    bezierPoints = "[" + (0..<expected).map { index in
      guard index < source.count else { return "null" }
      let point = source[index]
      return "{\"leading\":[\(_meshNumber(point.leadingControlPoint[0])),\(_meshNumber(point.leadingControlPoint[1]))],\"top\":[\(_meshNumber(point.topControlPoint[0])),\(_meshNumber(point.topControlPoint[1]))],\"trailing\":[\(_meshNumber(point.trailingControlPoint[0])),\(_meshNumber(point.trailingControlPoint[1]))],\"bottom\":[\(_meshNumber(point.bottomControlPoint[0])),\(_meshNumber(point.bottomControlPoint[1]))]}"
    }.joined(separator: ",") + "]"
  }
  return "{\"width\":\(mesh._meshWidth),\"height\":\(mesh._meshHeight),\"points\":[\(points)],\"bezierPoints\":\(bezierPoints),\"colors\":[\(colors)],\"background\":\(_meshJSONString(mesh.background.cssValue)),\"smoothsColors\":\(mesh.smoothsColors ? "true" : "false"),\"colorSpace\":\(_meshJSONString(mesh.colorSpace.rawValue))}"
}

private func _meshGradientFingerprint(_ mesh: MeshGradient) -> String {
  var hasher = Hasher()
  hasher.combine(mesh.width); hasher.combine(mesh.height); hasher.combine(mesh.smoothsColors); hasher.combine(mesh.colorSpace); hasher.combine(mesh.locations)
  hasher.combine(mesh.background)
  for point in _meshPoints(mesh) { hasher.combine(point[0]); hasher.combine(point[1]) }
  for color in _meshColors(mesh) { hasher.combine(color) }
  return String(hasher.finalize())
}

/// Retained per-canvas storage: the size the host last reported and the size the drawing last used.
final class _CanvasSizeStore {
  var latest = SwiftUIWebCanvasSize(width: 0, height: 0)
  var rendered = SwiftUIWebCanvasSize(width: 0, height: 0)
  var hasHostMeasurement = false
}

public nonisolated struct Canvas<Symbols: View>: View, _OwnerBoundaryContent {
  public typealias Body = Never
  @State(memberID: 3649057291) private var store = _CanvasSizeStore()
  public nonisolated var isOpaque: Bool
  public nonisolated var colorMode: ColorRenderingMode
  public nonisolated var rendersAsynchronously: Bool
  public var renderer: (inout GraphicsContext, CGSize) -> Void
  /// The tagged child views the renderer draws with `GraphicsContext.resolveSymbol(id:)`.
  public var symbols: Symbols
  /// SwiftUIWeb's non-Apple symbol providers (`GraphicsContext.Symbols`) resolve symbols without a view.
  private let symbolProvider: (@MainActor (_RenderContext) -> GraphicsContext.Symbols)?

  package init(opaque: Bool, colorMode: ColorRenderingMode, rendersAsynchronously: Bool, renderer: @escaping (inout GraphicsContext, CGSize) -> Void, symbols: Symbols, symbolProvider: (@MainActor (_RenderContext) -> GraphicsContext.Symbols)?) {
    self.isOpaque = opaque
    self.colorMode = colorMode
    self.rendersAsynchronously = rendersAsynchronously
    self.renderer = renderer
    self.symbols = symbols
    self.symbolProvider = symbolProvider
  }

  /// Apple's view-builder form: each tagged child view is a symbol the renderer can draw.
  nonisolated public init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false, renderer: @escaping (inout GraphicsContext, CGSize) -> Void, @ViewBuilder symbols: () -> Symbols) {
    self.init(opaque: opaque, colorMode: colorMode, rendersAsynchronously: rendersAsynchronously, renderer: renderer, symbols: symbols(), symbolProvider: nil)
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    // The drawing closure receives the size the canvas was laid out at, which only the host knows. As a
    // `GeometryReader` does, the canvas is its own render owner and redraws when the host reports a new size.
    AnyView(_ownerBoundaryOf: self)._render(in: context)
  }

  @MainActor package func _renderOwnerBoundary(in context: _RenderContext) -> _RenderNode { _renderCanvas(in: context) }

  @MainActor private func _renderCanvas(in context: _RenderContext) -> _RenderNode {
    let previousScope = StateRuntime.scope
    StateRuntime.scope = StateScope(context: context, viewTag: "Canvas")
    defer { StateRuntime.scope = previousScope }
    let store = self.store
    let proposal = context._layoutProposal
    var width = proposal?.width?.isFinite == true ? max(0, Double(proposal!.width!)) : 300
    var height = proposal?.height?.isFinite == true ? max(0, Double(proposal!.height!)) : 150
    if store.hasHostMeasurement { width = store.latest.width; height = store.latest.height }
    store.rendered = SwiftUIWebCanvasSize(width: width, height: height)
    let size = SwiftUIWebCanvasSize(width: width, height: height)
    var symbolValues = GraphicsContext.Symbols()
    if let symbolProvider {
      symbolValues = symbolProvider(context)
    } else {
      // Resolve symbol views in Canvas's environment/fiber scope so inherited state, font and foreground values
      // remain coherent with the views they are drawn as.
      _collectCanvasSymbols(from: symbols._render(in: context.child(_FiberKey("canvas-symbols"))), into: &symbolValues)
    }
    var graphics = GraphicsContext(size: size, environment: context.environment, symbols: symbolValues)
    renderer(&graphics, size)
    let node = _RenderNode.element("canvas")
    node.classes = ["draw-canvas"]
    node.attributes["data-draw-canvas"] = "true"
    node.attributes["data-canvas-color-mode"] = colorMode.rawValue
    node.attributes["data-canvas-opaque"] = isOpaque ? "true" : "false"
    node.attributes["data-canvas-async"] = rendersAsynchronously ? "true" : "false"
    node.attributes["data-canvas-size"] = "\(_pathNumber(width)),\(_pathNumber(height))"
    node.attributes["data-canvas-command-count"] = String(graphics.commands.count)
    let fingerprint = _canvasFingerprint(graphics.commands)
    node.attributes["data-canvas-fingerprint"] = fingerprint
    node.styles["display"] = "block"
    if proposal?.width?.isFinite == true { node.styles["width"] = "\(_pathNumber(width))px" }
    if proposal?.height?.isFinite == true { node.styles["height"] = "\(_pathNumber(height))px" }
    node.attributes["data-canvas-commands"] = _canvasWire(graphics.commands)
    // Hosts report the box the layout gave the canvas through the GeometryReader channel (size only).
    node.attributes["data-geometry-reader"] = "true"
    let ownerToken = context._renderOwnerToken
    let invalidationStore = context.stateStore
    node.events["geometry"] = _EventHandler(name: "geometry", action: { rawValue in
      guard let next = _GeometryMeasurement(decoding: rawValue) else { return }
      let nextWidth = Double(next.size.width), nextHeight = Double(next.size.height)
      store.latest = SwiftUIWebCanvasSize(width: nextWidth, height: nextHeight)
      store.hasHostMeasurement = true
      guard nextWidth != Double(store.rendered.width) || nextHeight != Double(store.rendered.height) else { return }
      store.rendered = SwiftUIWebCanvasSize(width: nextWidth, height: nextHeight)
      if let ownerToken { invalidationStore._ownerObservationDidChange(ownerToken) }
    })
    node._canvasCommands = graphics.commands
    node._canvasFingerprint = fingerprint
    return node
  }
}

private func _canvasStops(_ gradient: Gradient) -> [_CanvasColorStop] {
  gradient.stops.map { _CanvasColorStop(color: $0.color.cssValue, location: $0.location) }
}

/// How a gradient continues beyond its 0...1 ramp. `pad` is the Canvas 2D
/// default; `repeat` and `mirror` are expanded into padded stops because the
/// Canvas gradient API has no tiling mode.
fileprivate enum _GradientSpread: Equatable, Sendable {
  case pad
  case `repeat`
  case mirror

  init(_ options: GraphicsContext.GradientOptions) {
    if options.contains(.mirror) {
      self = .mirror
    } else if options.contains(.`repeat`) {
      self = .`repeat`
    } else {
      self = .pad
    }
  }
}

/// Returns the shading to record for a fill or stroke whose geometry spans
/// `bounds`. Only geometry inside the bounds is painted, so the expansion
/// needs to cover just those ramp coordinates.
fileprivate extension GraphicsContext.Shading {
  /// The shading a fill or stroke paints with inside `bounds`: palettes, hierarchical levels and unit-point gradients
  /// become concrete paints, so every recorded shading is one of the plain cases.
  func flattened(in bounds: CGRect) -> GraphicsContext.Shading {
    GraphicsContext.Shading(storage: _canvasFlattened(storage, in: bounds), spread: spread)
  }
}

/// The paint a foreground-styled drawing (text, a system image) takes. Level 0 is the environment foreground, which
/// `color` carries, and a palette picks its level-0 entry, since a glyph and a text run have a single layer.
fileprivate func _canvasForeground(_ shading: _CanvasShading, color: String, in bounds: CGRect) -> _CanvasShading {
  switch shading {
  case .level(0): return .color(color)
  case .palette(let entries):
    guard !entries.isEmpty else { return .color("transparent") }
    return _canvasForeground(entries[0], color: color, in: bounds)
  default: return _canvasFlattened(shading, in: bounds)
  }
}

/// The CSS color a single-color paint stands for; gradients cannot paint a symbol's element color and fall back.
fileprivate func _canvasColorValue(_ shading: _CanvasShading, fallback: String) -> String {
  if case .color(let value) = shading { return value }
  return fallback
}

/// The box a drawing covers when `size` is placed at `point` with `anchor` (a unit point of that box).
fileprivate func _canvasBox(_ size: CGSize, at point: CGPoint, anchor: UnitPoint) -> CGRect {
  CGRect(x: point.x - anchor.x * size.width, y: point.y - anchor.y * size.height, width: size.width, height: size.height)
}

/// Resolves palettes, hierarchical levels and unit-point gradients to concrete paints (see `_CanvasShading`).
fileprivate func _canvasFlattened(_ shading: _CanvasShading, in bounds: CGRect, level: Int = 0) -> _CanvasShading {
  switch shading {
  case .palette(let entries):
    // Level n of a palette paints with entry min(n, count - 1), as Apple's `Shading.palette(_:)` does.
    guard !entries.isEmpty else { return .color("transparent") }
    return _canvasFlattened(entries[min(max(0, level), entries.count - 1)], in: bounds)
  case .level(let level):
    return .color(HierarchicalShapeStyle(level: level)._swiftUIWebCSSValue)
  case .unitGradient(let gradient):
    func point(_ unit: UnitPoint) -> CGPoint {
      CGPoint(x: bounds.minX + unit.x * bounds.width, y: bounds.minY + unit.y * bounds.height)
    }
    switch gradient {
    case .linear(let stops, let start, let end):
      return .linear(stops: stops, start: point(start), end: point(end))
    case .radial(let stops, let center, let startRadius, let endRadius):
      let resolved = point(center)
      return .radial(stops: stops, center: resolved, startRadius: startRadius, endRadius: endRadius, endCenter: resolved)
    case .angular(let stops, let center, let startAngle, let endAngle):
      return .angular(stops: stops, center: point(center), startAngle: startAngle, endAngle: endAngle)
    }
  default:
    return shading
  }
}

fileprivate func _spreadExpanded(_ shading: GraphicsContext.Shading, bounds: CGRect) -> _CanvasShading {
  guard shading.spread != .pad else { return shading.storage }
  return _expandGradientSpread(shading.storage, spread: shading.spread, bounds: bounds) ?? shading.storage
}

private func _expandGradientSpread(_ shading: _CanvasShading, spread: _GradientSpread, bounds: CGRect) -> _CanvasShading? {
  guard bounds.minX.isFinite, bounds.minY.isFinite, bounds.maxX.isFinite, bounds.maxY.isFinite else { return nil }
  switch shading {
  case .color, .tiled, .level, .palette, .unitGradient:
    return nil
  case .linear(let stops, let start, let end):
    return _expandLinearSpread(stops, start: start, end: end, spread: spread, bounds: bounds)
  case .radial(let stops, let center, let startRadius, let endRadius, let endCenter):
    return _expandRadialSpread(stops, center: center, startRadius: startRadius, endRadius: endRadius, endCenter: endCenter, spread: spread, bounds: bounds)
  case .angular(let stops, let center, let startAngle, let endAngle):
    // A conic ramp already spans one full turn, so `repeat` has no effect.
    // `mirror` folds the turn so that the second half reverses the first.
    guard spread == .mirror, let ramp = _rampStops(stops) else { return nil }
    let turn = _normalizedStops(_tiledStops(ramp, spread: .mirror, from: 0, to: 2), from: 0, to: 2)
    return .angular(stops: turn, center: center, startAngle: startAngle, endAngle: endAngle)
  }
}

/// The ramp one period of a repeated or mirrored gradient is made of. Ramps
/// that do not reach 0 or 1 are padded with their end colors, as Canvas does.
private func _rampStops(_ stops: [_CanvasColorStop]) -> [_CanvasColorStop]? {
  var ramp = stops.sorted { $0.location < $1.location }
  guard let first = ramp.first, let last = ramp.last else { return nil }
  if first.location > 0 { ramp.insert(_CanvasColorStop(color: first.color, location: 0), at: 0) }
  if last.location < 1 { ramp.append(_CanvasColorStop(color: last.color, location: 1)) }
  return ramp
}

/// A stop before normalisation. Its location is a ramp coordinate that may lie
/// far beyond 0...1, so it must not go through `_CanvasColorStop`, which clamps.
private typealias _RampStop = (color: String, location: Double)

/// Stops of `ramp` tiled over the periods in `from..<to`, in ramp units. A
/// repeat period is the ramp itself. A mirror period is the ramp followed by
/// its reverse, which makes the seam between periods continuous.
private func _tiledStops(_ ramp: [_CanvasColorStop], spread: _GradientSpread, from: Int, to: Int) -> [_RampStop] {
  var out: [_RampStop] = []
  let period = spread == .mirror ? 2 : 1
  var index = from
  while index < to {
    let base = Double(index)
    for stop in ramp {
      out.append((color: stop.color, location: base + stop.location))
    }
    if spread == .mirror {
      for stop in ramp.reversed() {
        out.append((color: stop.color, location: base + 2 - stop.location))
      }
    }
    index += period
  }
  return out
}

/// Maps ramp coordinates in `from...to` onto Canvas offsets in 0...1.
private func _normalizedStops(_ stops: [_RampStop], from: Int, to: Int) -> [_CanvasColorStop] {
  let span = Double(to - from)
  return stops.map { _CanvasColorStop(color: $0.color, location: ($0.location - Double(from)) / span) }
}

/// The whole-period range that covers ramp coordinates `low...high`, aligned
/// so that both ends fall on a period boundary (and therefore on a stop).
private func _periodRange(low: Double, high: Double, spread: _GradientSpread) -> (from: Int, to: Int)? {
  let period = spread == .mirror ? 2 : 1
  guard abs(low) < 1_000_000, abs(high) < 1_000_000 else { return nil }
  let from = Int((low / Double(period)).rounded(.down)) * period
  var to = Int((high / Double(period)).rounded(.up)) * period
  if to <= from { to = from + period }
  guard (to - from) / period <= 1_024 else { return nil }
  return (from, to)
}

private func _expandLinearSpread(_ stops: [_CanvasColorStop], start: CGPoint, end: CGPoint, spread: _GradientSpread, bounds: CGRect) -> _CanvasShading? {
  let dx = end.x - start.x
  let dy = end.y - start.y
  let lengthSquared = dx * dx + dy * dy
  guard lengthSquared > 0, let ramp = _rampStops(stops) else { return nil }
  // Ramp coordinate is linear in position, so the corners bound the range.
  let coordinates = [
    CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
    CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY),
  ].map { (($0.x - start.x) * dx + ($0.y - start.y) * dy) / lengthSquared }
  guard let low = coordinates.min(), let high = coordinates.max(),
        let range = _periodRange(low: low, high: high, spread: spread) else { return nil }
  let from = Double(range.from)
  let to = Double(range.to)
  return .linear(
    stops: _normalizedStops(_tiledStops(ramp, spread: spread, from: range.from, to: range.to), from: range.from, to: range.to),
    start: CGPoint(x: start.x + from * dx, y: start.y + from * dy),
    end: CGPoint(x: start.x + to * dx, y: start.y + to * dy)
  )
}

/// Expands a radial gradient by parameterising its circles as
/// `c(s) = c0 + s * (c1 - c0)` and `r(s) = r0 + s * (r1 - r0)`. Canvas uses the
/// parameter `s` as the ramp coordinate for any two circles, so the periods
/// are laid out along `s` and the end circles are extended to cover the bounds.
private func _expandRadialSpread(
  _ stops: [_CanvasColorStop],
  center c0: CGPoint,
  startRadius r0: Double,
  endRadius r1: Double,
  endCenter c1: CGPoint,
  spread: _GradientSpread,
  bounds: CGRect
) -> _CanvasShading? {
  guard let ramp = _rampStops(stops), r0 >= 0, r1 >= 0 else { return nil }
  let dx = c1.x - c0.x
  let dy = c1.y - c0.y
  let dr = r1 - r0
  // A point p is on circle s when |p - c(s)|² = r(s)², with r(s) >= 0.
  let a = dx * dx + dy * dy - dr * dr
  let midX = (bounds.minX + bounds.maxX) / 2
  let midY = (bounds.minY + bounds.maxY) / 2
  let samples = [
    CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: midX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
    CGPoint(x: bounds.minX, y: midY), CGPoint(x: midX, y: midY), CGPoint(x: bounds.maxX, y: midY),
    CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: midX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY),
  ]
  var lowS = Double.infinity
  var highS = -Double.infinity
  for p in samples {
    let qx = p.x - c0.x
    let qy = p.y - c0.y
    let b = -2 * (qx * dx + qy * dy + r0 * dr)
    let c = qx * qx + qy * qy - r0 * r0
    for s in _quadraticRoots(a, b, c) where r0 + s * dr >= 0 {
      lowS = min(lowS, s)
      highS = max(highS, s)
    }
  }
  // A nearly degenerate pair of circles puts the parameters far out; past a million periods there is nothing to tile, and
  // Int(_:) of the quotient would trap where Int is 32 bits.
  guard lowS.isFinite, highS.isFinite, abs(lowS) < 1_000_000, abs(highS) < 1_000_000 else { return nil }
  let period = spread == .mirror ? 2 : 1
  // Widen by one period on each side so that rounding never exposes a pad.
  let lowPeriods = Int((lowS / Double(period)).rounded(.down)) - 1
  let highPeriods = Int((highS / Double(period)).rounded(.up)) + 1
  var from = lowPeriods * period
  var to = highPeriods * period
  // The end circles must keep a non-negative radius. r(s) is monotonic, so
  // the valid parameters form a half-line that the range is clipped to.
  if dr != 0 {
    let boundary = -r0 / dr
    guard abs(boundary) < 1_000_000 else { return nil }
    if dr > 0 {
      from = max(from, Int((boundary / Double(period)).rounded(.up)) * period)
    } else {
      to = min(to, Int((boundary / Double(period)).rounded(.down)) * period)
    }
  }
  guard to > from, (to - from) / period <= 1_024 else { return nil }
  let f = Double(from)
  let t = Double(to)
  return .radial(
    stops: _normalizedStops(_tiledStops(ramp, spread: spread, from: from, to: to), from: from, to: to),
    center: CGPoint(x: c0.x + f * dx, y: c0.y + f * dy),
    startRadius: r0 + f * dr,
    endRadius: r0 + t * dr,
    endCenter: CGPoint(x: c0.x + t * dx, y: c0.y + t * dy)
  )
}

private func _quadraticRoots(_ a: Double, _ b: Double, _ c: Double) -> [Double] {
  if abs(a) < 1e-12 {
    return abs(b) < 1e-12 ? [] : [-c / b]
  }
  let discriminant = b * b - 4 * a * c
  guard discriminant >= 0 else { return [] }
  let root = discriminant.squareRoot()
  return [(-b + root) / (2 * a), (-b - root) / (2 * a)]
}

private func _canvasShading<S: ShapeStyle>(_ style: S, in size: SwiftUIWebCanvasSize) -> _CanvasShading {
  let width = Double(size.width)
  let height = Double(size.height)
  // A hierarchical level stays a level until the context resolves it against its foreground styles.
  if let level = style as? HierarchicalShapeStyle { return .level(level.level) }
  if let color = style._swiftUIWebSolidColor { return .color(color.cssValue) }
  if let gradient = style as? LinearGradient {
    return .linear(stops: _canvasStops(gradient.gradient), start: CGPoint(x: gradient.startPoint.x * width, y: gradient.startPoint.y * height), end: CGPoint(x: gradient.endPoint.x * width, y: gradient.endPoint.y * height))
  }
  if let gradient = style as? RadialGradient {
    return .radial(stops: _canvasStops(gradient.gradient), center: CGPoint(x: gradient.center.x * width, y: gradient.center.y * height), startRadius: gradient.startRadius, endRadius: gradient.endRadius, endCenter: CGPoint(x: gradient.center.x * width, y: gradient.center.y * height))
  }
  if let gradient = style as? AngularGradient {
    return .angular(stops: _canvasStops(gradient.gradient), center: CGPoint(x: gradient.center.x * width, y: gradient.center.y * height), startAngle: gradient.startAngle.radians, endAngle: gradient.endAngle.radians)
  }
  return .color(style._swiftUIWebCSSValue)
}

private func _canvasPath<S: Shape>(for shape: S, in size: SwiftUIWebCanvasSize) -> Path {
  if let path = shape as? Path { return path }
  let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: size.width, height: size.height))
  // Every Shape, including built-ins and custom application shapes, now
  // participates through the same public path(in:) witness. This preserves
  // inset geometry and avoids a second Canvas-only shape taxonomy.
  return shape.path(in: rect)
}

private func _canvasFont(_ font: Font) -> String {
  let styles = font.cssStyles
  let size = styles["font-size"] ?? "17px"
  let weight = styles["font-weight"] ?? "400"
  let family = styles["font-family"] ?? "system-ui"
  let style = styles["font-style"] ?? "normal"
  return "\(style) \(weight) \(size) \(family)"
}

private func _canvasFontSize(_ font: Font) -> Double {
  guard let raw = font.cssStyles["font-size"] else { return 17 }
  // Foundation's CharacterSet/String trimming APIs are not available in the
  // WASI SDK.  Canvas font sizes are serialized as CSS pixels, so strip the
  // optional suffix explicitly and keep the parser deterministic on every
  // target.
  let value = raw.hasSuffix("px") ? String(raw.dropLast(2)) : raw
  return Double(value) ?? 17
}

private func _canvasSine(_ value: Double) -> Double {
  let reduced = _canvasReducedAngle(value)
  let square = reduced * reduced
  return reduced * (1 - square / 6 + square * square / 120 - square * square * square / 5_040)
}

private func _canvasCosine(_ value: Double) -> Double {
  let reduced = _canvasReducedAngle(value)
  let square = reduced * reduced
  return 1 - square / 2 + square * square / 24 - square * square * square / 720
}

private func _canvasReducedAngle(_ value: Double) -> Double {
  let tau = 6.283185307179586
  guard value.isFinite else { return 0 }
  // The IEEE remainder is in [-pi, pi] at once; subtracting a turn at a time never ends for an angle of 1e17 radians.
  return value.remainder(dividingBy: tau)
}

/// The drawing as JSON for a host that paints it (the browser's 2D context). Paths travel as SVG path data.
@MainActor private func _canvasWire(_ commands: [_CanvasCommand]) -> String {
  func n(_ value: Double) -> String { _pathNumber(value) }
  func q(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      default: if scalar.value < 0x20 { out += "\\u00" + (scalar.value < 16 ? "0" : "1") + String(scalar.value % 16, radix: 16) } else { out.unicodeScalars.append(scalar) }
      }
    }
    return out + "\""
  }
  func d(_ values: [String]) -> String {
    var path = Path()
    path.commands = values
    return q(path._svgPathData)
  }
  func stops(_ values: [_CanvasColorStop]) -> String {
    "[" + values.map { "[" + q($0.color) + "," + _rampNumber($0.location) + "]" }.joined(separator: ",") + "]"
  }
  func shading(_ value: _CanvasShading) -> String {
    switch value {
    // Fills and strokes resolve these at record time (`flattened(in:)`), so they never reach the host.
    case .palette, .level, .unitGradient: return "{\"k\":\"c\",\"c\":\"transparent\"}"
    case .color(let color): return "{\"k\":\"c\",\"c\":" + q(color) + "}"
    case .linear(let s, let start, let end):
      return "{\"k\":\"l\",\"s\":" + stops(s) + ",\"x0\":" + n(Double(start.x)) + ",\"y0\":" + n(Double(start.y)) + ",\"x1\":" + n(Double(end.x)) + ",\"y1\":" + n(Double(end.y)) + "}"
    case .radial(let s, let center, let startRadius, let endRadius, let endCenter):
      return "{\"k\":\"r\",\"s\":" + stops(s) + ",\"x\":" + n(Double(center.x)) + ",\"y\":" + n(Double(center.y)) + ",\"r0\":" + n(startRadius) + ",\"r1\":" + n(endRadius) + ",\"x1\":" + n(Double(endCenter.x)) + ",\"y1\":" + n(Double(endCenter.y)) + "}"
    case .angular(let s, let center, let startAngle, _):
      return "{\"k\":\"a\",\"s\":" + stops(s) + ",\"x\":" + n(Double(center.x)) + ",\"y\":" + n(Double(center.y)) + ",\"a\":" + n(startAngle) + "}"
    case .tiled(let name, let origin, let rect, let scale):
      return "{\"k\":\"p\",\"src\":" + source(name) + ",\"ox\":" + n(Double(origin.x)) + ",\"oy\":" + n(Double(origin.y))
        + ",\"sx\":" + n(Double(rect.minX)) + ",\"sy\":" + n(Double(rect.minY)) + ",\"sw\":" + n(Double(rect.width)) + ",\"sh\":" + n(Double(rect.height)) + ",\"z\":" + n(scale) + "}"
    }
  }
  func source(_ name: String) -> String { q(_ImageAssets.source(forMarked: name) ?? "") }
  var out = "["
  var first = true
  for command in commands {
    var item: String
    switch command {
    case .fill(let path, let value, let eoFill): item = "{\"o\":\"f\",\"d\":" + d(path) + ",\"s\":" + shading(value) + ",\"eo\":" + (eoFill ? "1" : "0") + "}"
    case .stroke(let path, let value, let style):
      item = "{\"o\":\"s\",\"d\":" + d(path) + ",\"s\":" + shading(value) + ",\"w\":" + n(style.lineWidth) + ",\"cap\":" + q(style._svgLineCap) + ",\"join\":" + q(style._svgLineJoin) + ",\"ml\":" + n(style.miterLimit) + ",\"dash\":[" + style.dash.map(n).joined(separator: ",") + "],\"dp\":" + n(style.dashPhase) + "}"
    case .clip(let path, let eoFill): item = "{\"o\":\"c\",\"d\":" + d(path) + ",\"eo\":" + (eoFill ? "1" : "0") + "}"
    case .save: item = "{\"o\":\"save\"}"
    case .restore: item = "{\"o\":\"restore\"}"
    case .translate(let x, let y): item = "{\"o\":\"t\",\"x\":" + n(x) + ",\"y\":" + n(y) + "}"
    case .scale(let x, let y): item = "{\"o\":\"sc\",\"x\":" + n(x) + ",\"y\":" + n(y) + "}"
    case .rotate(let radians): item = "{\"o\":\"r\",\"a\":" + n(radians) + "}"
    case .setTransform(let a, let b, let c, let dd, let tx, let ty): item = "{\"o\":\"m\",\"m\":[" + [a, b, c, dd, tx, ty].map(n).joined(separator: ",") + "]}"
    case .opacity(let value): item = "{\"o\":\"a\",\"v\":" + n(value) + "}"
    case .blendMode(let mode): item = "{\"o\":\"b\",\"v\":" + q(mode.canvasOperation) + "}"
    case .filter(let value): item = "{\"o\":\"fl\",\"v\":" + q(value) + "}"
    case .text(let value, let point, let anchor, let paint, let font):
      item = "{\"o\":\"tx\",\"t\":" + q(value) + ",\"x\":" + n(Double(point.x)) + ",\"y\":" + n(Double(point.y)) + ",\"ax\":" + n(anchor.x) + ",\"ay\":" + n(anchor.y) + ",\"s\":" + shading(paint) + ",\"f\":" + q(font) + "}"
    case .image(let name, let rect, let point, let anchor):
      item = "{\"o\":\"i\",\"src\":" + source(name)
      if let rect { item += ",\"x\":" + n(Double(rect.origin.x)) + ",\"y\":" + n(Double(rect.origin.y)) + ",\"w\":" + n(Double(rect.size.width)) + ",\"h\":" + n(Double(rect.size.height)) }
      if let point { item += ",\"px\":" + n(Double(point.x)) + ",\"py\":" + n(Double(point.y)) }
      item += ",\"ax\":" + n(anchor.x) + ",\"ay\":" + n(anchor.y) + "}"
    case .symbol(let markup, let fallback, let point, let anchor, let font, let color):
      item = "{\"o\":\"sym\",\"m\":" + q(markup) + ",\"t\":" + q(fallback) + ",\"x\":" + n(Double(point.x)) + ",\"y\":" + n(Double(point.y)) + ",\"ax\":" + n(anchor.x) + ",\"ay\":" + n(anchor.y) + ",\"c\":" + q(color) + ",\"f\":" + q(font) + "}"
    case .resetState: item = "{\"o\":\"rs\"}"
    case .glyphs(let value, let x, let y, let font, let color, let spacing, let rightToLeft, let paint):
      // The paint is a shading object the page measured; one that is not an object is left out.
      let shading = paint.hasPrefix("{") && paint.hasSuffix("}") ? ",\"p\":" + paint : ""
      item = "{\"o\":\"gl\",\"t\":" + q(value) + ",\"x\":" + n(x) + ",\"y\":" + n(y) + ",\"f\":" + q(font) + ",\"c\":" + q(color) + ",\"ls\":" + n(spacing) + ",\"rtl\":" + (rightToLeft ? "1" : "0") + shading + "}"
    case .textDecoration(let x0, let x1, let y, let thickness, let color):
      item = "{\"o\":\"td\",\"x0\":" + n(x0) + ",\"x1\":" + n(x1) + ",\"y\":" + n(y) + ",\"th\":" + n(thickness) + ",\"c\":" + q(color) + "}"
    }
    if first { first = false } else { out += "," }
    out += item
  }
  return out + "]"
}

private func _canvasFingerprint(_ commands: [_CanvasCommand]) -> String {
  // Keep the DOM metadata compact even for a 100k-command drawing.  The
  // process-local Hasher is sufficient because fingerprints are only compared
  // within one Fiber/browser session; the full command values remain on the
  // semantic _RenderNode for the backend.
  var hasher = Hasher()
  hasher.combine(commands.count)
  for command in commands { _combineCanvasCommand(command, into: &hasher) }
  return String(hasher.finalize())
}

private func _combineCanvasCommand(_ command: _CanvasCommand, into hasher: inout Hasher) {
  func path(_ values: [String]) { hasher.combine(values.count); for value in values { hasher.combine(value) } }
  func shading(_ value: _CanvasShading) {
    switch value {
    case .palette, .level, .unitGradient: hasher.combine(5)
    case .color(let color): hasher.combine(0); hasher.combine(color)
    case .linear(let stops, let start, let end):
      hasher.combine(1); hasher.combine(stops.count); for stop in stops { hasher.combine(stop.color); hasher.combine(stop.location) }; hasher.combine(start.x); hasher.combine(start.y); hasher.combine(end.x); hasher.combine(end.y)
    case .radial(let stops, let center, let startRadius, let endRadius, let endCenter):
      hasher.combine(endCenter.x); hasher.combine(endCenter.y); hasher.combine(2); hasher.combine(stops.count); for stop in stops { hasher.combine(stop.color); hasher.combine(stop.location) }; hasher.combine(center.x); hasher.combine(center.y); hasher.combine(startRadius); hasher.combine(endRadius)
    case .angular(let stops, let center, let startAngle, let endAngle):
      hasher.combine(3); hasher.combine(stops.count); for stop in stops { hasher.combine(stop.color); hasher.combine(stop.location) }; hasher.combine(center.x); hasher.combine(center.y); hasher.combine(startAngle); hasher.combine(endAngle)
    case .tiled(let source, let origin, let rect, let scale):
      hasher.combine(4); hasher.combine(source); hasher.combine(origin.x); hasher.combine(origin.y)
      hasher.combine(rect.minX); hasher.combine(rect.minY); hasher.combine(rect.width); hasher.combine(rect.height); hasher.combine(scale)
    }
  }
  switch command {
  case .fill(let values, let value, let eoFill): hasher.combine(0); path(values); shading(value); hasher.combine(eoFill)
  case .stroke(let values, let value, let style): hasher.combine(1); path(values); shading(value); hasher.combine(style)
  case .clip(let values, let eoFill): hasher.combine(2); path(values); hasher.combine(eoFill)
  case .save: hasher.combine(3)
  case .restore: hasher.combine(4)
  case .translate(let x, let y): hasher.combine(5); hasher.combine(x); hasher.combine(y)
  case .scale(let x, let y): hasher.combine(6); hasher.combine(x); hasher.combine(y)
  case .rotate(let radians): hasher.combine(7); hasher.combine(radians)
  case .setTransform(let a, let b, let c, let d, let tx, let ty): hasher.combine(8); hasher.combine(a); hasher.combine(b); hasher.combine(c); hasher.combine(d); hasher.combine(tx); hasher.combine(ty)
  case .opacity(let value): hasher.combine(9); hasher.combine(value)
  case .blendMode(let mode): hasher.combine(10); hasher.combine(mode.rawValue)
  case .filter(let value): hasher.combine(17); hasher.combine(value)
  case .text(let value, let point, let anchor, let paint, let font): hasher.combine(11); hasher.combine(value); hasher.combine(point.x); hasher.combine(point.y); hasher.combine(anchor.x); hasher.combine(anchor.y); shading(paint); hasher.combine(font)
  case .image(let source, let rect, let point, let anchor): hasher.combine(12); hasher.combine(source); if let rect { hasher.combine(rect.origin.x); hasher.combine(rect.origin.y); hasher.combine(rect.size.width); hasher.combine(rect.size.height) }; if let point { hasher.combine(point.x); hasher.combine(point.y) }; hasher.combine(anchor.x); hasher.combine(anchor.y)
  case .symbol(let markup, let fallback, let point, let anchor, let font, let color): hasher.combine(13); hasher.combine(markup); hasher.combine(fallback); hasher.combine(point.x); hasher.combine(point.y); hasher.combine(anchor.x); hasher.combine(anchor.y); hasher.combine(font); hasher.combine(color)
  case .resetState: hasher.combine(15)
  case .glyphs(let value, let x, let y, let font, let color, let spacing, let rightToLeft, let paint): hasher.combine(14); hasher.combine(value); hasher.combine(x); hasher.combine(y); hasher.combine(font); hasher.combine(color); hasher.combine(spacing); hasher.combine(rightToLeft); hasher.combine(paint)
  case .textDecoration(let x0, let x1, let y, let thickness, let color): hasher.combine(16); hasher.combine(x0); hasher.combine(x1); hasher.combine(y); hasher.combine(thickness); hasher.combine(color)
  }
}

/// One resolved symbol: its fallback label, its markup, and the frame it declares (zero when it declares none).
fileprivate struct _CanvasSymbolEntry: Hashable, Sendable {
  let fallback: String
  let markup: String
  let size: CGSize
}

private func _collectCanvasSymbols(from node: _RenderNode, into symbols: inout GraphicsContext.Symbols) {
  // The tag attribute is already the `fiberKeyDescription` of the tag value, the key `resolveSymbol(id:)` looks up.
  if let id = node.attributes["data-tag"] {
    let text = node.text ?? node.children.compactMap({ $0.text }).joined(separator: " ")
    symbols.entries[id] = _CanvasSymbolEntry(fallback: text, markup: _canvasMarkup(node), size: _canvasFrameSize(node))
  }
  for child in node.children { _collectCanvasSymbols(from: child, into: &symbols) }
}

/// The frame a node declares in pixels, from its `width` and `height` styles.
private func _canvasFrameSize(_ node: _RenderNode) -> CGSize {
  func pixels(_ value: String?) -> CGFloat {
    guard let value, value.hasSuffix("px"), let number = Double(String(value.dropLast(2))) else { return 0 }
    return CGFloat(number)
  }
  return CGSize(width: pixels(node.styles["width"]), height: pixels(node.styles["height"]))
}

/// The HTML a node draws as: its element, classes, attributes and inline styles, with its children. Event handlers and
/// the tag key are not part of the drawing. The page parses this markup (`innerHTML`) to measure it, so it passes the
/// same filters as the rest of the page's markup: no executing element, no `on…` attribute, no `javascript:` URL.
private func _canvasMarkup(_ node: _RenderNode) -> String {
  switch node.kind {
  case .text:
    guard let text = node.text else { return "" }
    return _canvasEscapeHTML(text)
  case .element(let tag):
    guard _isSafeElementName(tag) else { return "" }
    var out = "<" + tag
    if !node.classes.isEmpty { out += " class=\"" + _canvasEscapeHTML(node.classes.joined(separator: " ")) + "\"" }
    for (name, value) in node.attributes.sorted(by: { $0.key < $1.key }) where name != "data-tag" {
      // The mounted-element filter: event handlers, srcdoc and script URLs go, while the image schemes an Image may use
      // (data:, blob:) stay, so a symbol's image keeps its source.
      guard let safe = _safeMountedAttributeValue(name: name, value: value) else { continue }
      out += " " + name + "=\"" + _canvasEscapeHTML(safe) + "\""
    }
    if !node.styles.isEmpty {
      out += " style=\"" + node.styles.sorted(by: { $0.key < $1.key }).map { _canvasEscapeHTML($0.key + ":" + $0.value) }.joined(separator: ";") + "\""
    }
    out += ">"
    out += node.children.map(_canvasMarkup).joined()
    if !["img", "br", "hr", "input"].contains(tag) { out += "</" + tag + ">" }
    return out
  case .fragment, .empty:
    return node.children.map(_canvasMarkup).joined()
  }
}

fileprivate func _canvasEscapeHTML(_ text: String) -> String {
  var out = ""
  for scalar in text.unicodeScalars {
    switch scalar {
    case "&": out += "&amp;"
    case "<": out += "&lt;"
    case ">": out += "&gt;"
    case "\"": out += "&quot;"
    case "'": out += "&#39;"
    default: out.unicodeScalars.append(scalar)
    }
  }
  return out
}

extension MeshGradient: View {}
