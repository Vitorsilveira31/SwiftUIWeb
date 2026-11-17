// SwiftUI-shaped compatibility conveniences used by real applications.
// These modifiers carry compact semantic metadata; platform hosts can choose
// richer behavior without leaking DOM/WASM concepts into application code.

@_spi(Renderer) import SwiftUIWebTransferable

public enum Visibility: Hashable, Sendable { case automatic, visible, hidden 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  package var rawValue: String {
    switch self {
    case .automatic: "automatic"
    case .visible: "visible"
    case .hidden: "hidden"
    }
  }
}

public struct Angle: Hashable, Sendable {
  public let radians: Double
  public init(radians: Double) { self.radians = radians }
  public init() { self.radians = 0 }
  public static let zero = Angle(radians: 0)
  public static func degrees(_ value: Double) -> Angle { Angle(radians: value * 0.017453292519943295) }
  public static func radians(_ value: Double) -> Angle { Angle(radians: value) }
  public static func + (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians + rhs.radians) }
  public static func - (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians - rhs.radians) }
}

public struct EdgeInsets: Hashable, Sendable {
  public var top: Double
  public var leading: Double
  public var bottom: Double
  public var trailing: Double
  public init() {
    self.init(top: 0, leading: 0, bottom: 0, trailing: 0)
  }
  public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
    self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
  }
}

public enum ToolbarPlacement: Hashable, Sendable { case automatic, navigationBar, tabBar, bottomBar, windowToolbar 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  package var rawValue: String {
    switch self {
    case .automatic: "automatic"
    case .navigationBar: "navigationBar"
    case .tabBar: "tabBar"
    case .bottomBar: "bottomBar"
    case .windowToolbar: "windowToolbar"
    }
  }
}
public enum Material: Hashable, Sendable, ShapeStyle {
  case ultraThin, thin, regular, thick, ultraThick

  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .ultraThin: "ultraThin"
    case .thin: "thin"
    case .regular: "regular"
    case .thick: "thick"
    case .ultraThick: "ultraThick"
    }
  }

  public var _swiftUIWebCSSValue: String {
    let opacity: Int
    switch self {
    case .ultraThin: opacity = 28
    case .thin: opacity = 42
    case .regular: opacity = 58
    case .thick: opacity = 76
    case .ultraThick: opacity = 90
    }
    return "color-mix(in srgb, Canvas \(opacity)%, transparent)"
  }

}

/// Browser realization of the translucent material blur. Kept as a module
/// helper rather than another app-facing ShapeStyle requirement.
func _materialBackdropFilter(_ material: Material) -> String {
  let blur: Int
  switch material {
  case .ultraThin: blur = 4
  case .thin: blur = 8
  case .regular: blur = 14
  case .thick: blur = 22
  case .ultraThick: blur = 30
  }
  return "blur(\(blur)px) saturate(180%)"
}

public enum ButtonBorderShape: Hashable, Sendable {
  case automatic, capsule, circle, roundedRectangle(radius: Double)
}
/// SwiftUI's form style family. Built-in styles report their browser token
/// through the underscored `_swiftUIWebFormStyle`; app-defined styles keep the
/// automatic look.
@MainActor @preconcurrency public protocol FormStyle { nonisolated var _swiftUIWebFormStyle: String { get } }
public extension FormStyle { nonisolated var _swiftUIWebFormStyle: String { "automatic" } }
public nonisolated struct AutomaticFormStyle: FormStyle {
  public nonisolated init() {}
  public nonisolated var _swiftUIWebFormStyle: String { "automatic" }
}
public nonisolated struct ColumnsFormStyle: FormStyle {
  public nonisolated init() {}
  public nonisolated var _swiftUIWebFormStyle: String { "columns" }
}
public nonisolated struct GroupedFormStyle: FormStyle {
  public nonisolated init() {}
  public nonisolated var _swiftUIWebFormStyle: String { "grouped" }
}
public extension FormStyle where Self == AutomaticFormStyle { @MainActor @preconcurrency static var automatic: AutomaticFormStyle { AutomaticFormStyle() } }
public extension FormStyle where Self == ColumnsFormStyle { @MainActor @preconcurrency static var columns: ColumnsFormStyle { ColumnsFormStyle() } }
public extension FormStyle where Self == GroupedFormStyle { static nonisolated var grouped: GroupedFormStyle { GroupedFormStyle() } }

/// SwiftUI's list style family. Built-in styles report a browser token through
/// `_swiftUIWebListStyle`; the browser draws the matching look.
public protocol ListStyle { var _swiftUIWebListStyle: String { get } }
public extension ListStyle { var _swiftUIWebListStyle: String { "automatic" } }
public struct DefaultListStyle: ListStyle {
  public init() {}
  public var _swiftUIWebListStyle: String { "automatic" }
}
public struct PlainListStyle: ListStyle {
  public init() {}
  public var _swiftUIWebListStyle: String { "plain" }
}
public struct GroupedListStyle: ListStyle {
  public init() {}
  public var _swiftUIWebListStyle: String { "grouped" }
}
public struct InsetListStyle: ListStyle {
  public init() {}
  /// The browser's table draws its own row backgrounds; the flag is accepted for source compatibility.
  public init(alternatesRowBackgrounds: Bool) {}
  public var _swiftUIWebListStyle: String { "inset" }
}
public struct InsetGroupedListStyle: ListStyle {
  public init() {}
  public var _swiftUIWebListStyle: String { "insetGrouped" }
}
public struct SidebarListStyle: ListStyle {
  public init() {}
  public var _swiftUIWebListStyle: String { "sidebar" }
}
public extension ListStyle where Self == DefaultListStyle { static var automatic: DefaultListStyle { DefaultListStyle() } }
public extension ListStyle where Self == PlainListStyle { static var plain: PlainListStyle { PlainListStyle() } }
public extension ListStyle where Self == GroupedListStyle { static var grouped: GroupedListStyle { GroupedListStyle() } }
public extension ListStyle where Self == InsetListStyle {
  static var inset: InsetListStyle { InsetListStyle() }
  static func inset(alternatesRowBackgrounds: Bool) -> InsetListStyle { InsetListStyle(alternatesRowBackgrounds: alternatesRowBackgrounds) }
}
public extension ListStyle where Self == InsetGroupedListStyle { static var insetGrouped: InsetGroupedListStyle { InsetGroupedListStyle() } }
public extension ListStyle where Self == SidebarListStyle { static var sidebar: SidebarListStyle { SidebarListStyle() } }

/// SwiftUI's DatePicker style family. Browser hosts map these semantic tokens
/// to the closest native realization while keeping the public API independent
/// of HTML controls.
@MainActor @preconcurrency public protocol DatePickerStyle {
  var _swiftUIWebDatePickerStyle: String { get }
}
public extension DatePickerStyle {
  var _swiftUIWebDatePickerStyle: String { "automatic" }
}
@MainActor @preconcurrency public struct DefaultDatePickerStyle: DatePickerStyle {
  @MainActor @preconcurrency public init() {}
  public var _swiftUIWebDatePickerStyle: String { "automatic" }
}
public nonisolated struct CompactDatePickerStyle: DatePickerStyle {
  public nonisolated init() {}
  public var _swiftUIWebDatePickerStyle: String { "compact" }
}
public nonisolated struct FieldDatePickerStyle: DatePickerStyle {
  public nonisolated init() {}
  public var _swiftUIWebDatePickerStyle: String { "field" }
}
public extension DatePickerStyle where Self == DefaultDatePickerStyle {
  @MainActor @preconcurrency static var automatic: DefaultDatePickerStyle { DefaultDatePickerStyle() }
}
public extension DatePickerStyle where Self == CompactDatePickerStyle {
  @MainActor @preconcurrency static var compact: CompactDatePickerStyle { CompactDatePickerStyle() }
}
public extension DatePickerStyle where Self == FieldDatePickerStyle {
  @MainActor @preconcurrency static var field: FieldDatePickerStyle { FieldDatePickerStyle() }
}
/// SwiftUI's mask is an option set (rather than a closed enum), allowing
/// callers to combine `.gesture` and `.subviews`. The renderer serializes the
/// four practical combinations as stable names while retaining the native
/// OptionSet API for application code.
public struct GestureMask: OptionSet, Hashable, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public static let none: GestureMask = []
  public static let gesture = GestureMask(rawValue: 1 << 0)
  public static let subviews = GestureMask(rawValue: 1 << 1)
  public static let all: GestureMask = [.gesture, .subviews]
  fileprivate var _swiftUIWebName: String {
    if isEmpty { return "none" }
    if contains(.gesture) && contains(.subviews) { return "all" }
    return contains(.gesture) ? "gesture" : "subviews"
  }
}
public struct DynamicTypeSize: Hashable, Sendable {
  package let rawValue: String
  package init(_ rawValue: String) { self.rawValue = rawValue }
  public static let xSmall = DynamicTypeSize("xSmall")
  public static let small = DynamicTypeSize("small")
  public static let medium = DynamicTypeSize("medium")
  public static let large = DynamicTypeSize("large")
  public static let xLarge = DynamicTypeSize("xLarge")
  public static let xxLarge = DynamicTypeSize("xxLarge")
  public static let xxxLarge = DynamicTypeSize("xxxLarge")
  public static let accessibility1 = DynamicTypeSize("accessibility1")
  public static let accessibility2 = DynamicTypeSize("accessibility2")
  public static let accessibility3 = DynamicTypeSize("accessibility3")
  public static let accessibility4 = DynamicTypeSize("accessibility4")
  public static let accessibility5 = DynamicTypeSize("accessibility5")
  /// Matches SwiftUI's convenience query used by adaptive controls. The
  /// accessibility categories are the five largest dynamic type values.
  public var isAccessibilitySize: Bool {
    rawValue.hasPrefix("accessibility")
  }
}
/// SwiftUI's `ContentMarginPlacement`: the part of a scroll view that a content margin applies to.
public struct ContentMarginPlacement: Hashable, Sendable {
  let rawValue: String
  init(rawValue: String) { self.rawValue = rawValue }
  public static let automatic = ContentMarginPlacement(rawValue: "automatic")
  public static let scrollContent = ContentMarginPlacement(rawValue: "scrollContent")
  public static let scrollIndicators = ContentMarginPlacement(rawValue: "scrollIndicators")
}

/// SwiftUI's scroll target behavior. Built-in behaviors report their browser token
/// through the underscored `_swiftUIWebScrollTargetBehavior`; app-defined behaviors
/// are accepted and reported with a token the browser ignores.
public protocol ScrollTargetBehavior {
  var _swiftUIWebScrollTargetBehavior: String { get }
}
public extension ScrollTargetBehavior {
  var _swiftUIWebScrollTargetBehavior: String { "custom" }
}

/// A small SwiftUI-shaped visual effect value used by scroll transitions.
/// Effects are serialized as semantic properties and applied by the browser
/// host without exposing DOM or CSS types to application code.
/// SwiftUI's visual effect protocol. The effect methods live on the protocol, as in SwiftUI, and
/// each returns the same value type with one more semantic property. The browser host realizes the
/// accumulated properties; `_swiftUIWebEncoded` is the underscored hook it reads.
public protocol VisualEffect: Sendable {
  var _swiftUIWebProperties: [String: String] { get }
  init(_swiftUIWebProperties: [String: String])
  var _swiftUIWebEncoded: String { get }
}

public extension VisualEffect {
  func opacity(_ value: Double) -> Self { _swiftUIWebSetting("opacity", min(1, max(0, value)).clean) }
  func scaleEffect(x: Double = 1, y: Double = 1) -> Self { _swiftUIWebAppendingTransform("scale(\(x.clean),\(y.clean))") }
  func offset(x: Double = 0, y: Double = 0) -> Self { _swiftUIWebAppendingTransform("translate(\(x.clean)px,\(y.clean)px)") }
  func blur(radius: Double) -> Self { _swiftUIWebSetting("filter", "blur(\(max(0, radius).clean)px)") }

  fileprivate func _swiftUIWebSetting(_ key: String, _ value: String) -> Self {
    var copy = _swiftUIWebProperties
    copy[key] = value
    return Self(_swiftUIWebProperties: copy)
  }

  package func _swiftUIWebAppendingTransform(_ transform: String) -> Self {
    var copy = _swiftUIWebProperties
    copy["transform"] = [copy["transform"], transform].compactMap { $0 }.joined(separator: " ")
    return Self(_swiftUIWebProperties: copy)
  }
}

@propertyWrapper public struct GestureState<Value>: DynamicProperty {
  @MainActor private final class Storage {
    var box: StateBox<Value>
    var key: String?
    let initialValue: Value
    init(_ value: Value) { self.box = StateBox(value); self.key = nil; self.initialValue = value }

    func registeredBox() -> StateBox<Value> {
      guard let scope = StateRuntime.scope else { return box }
      // GestureState is commonly initialized while the view value is formed,
      // before its projected value is read. Retain that original Fiber key so a
      // later getter does not allocate a second state slot for the same box.
      let key: String
      if let existing = self.key {
        key = existing
      } else {
        key = scope.key()
        self.key = key
      }
      let registered = scope.store.register(box, key: key)
      box = registered
      return registered
    }
  }
  private let storage: Storage
  public init(wrappedValue: Value) {
    nonisolated(unsafe) let wrappedValue = wrappedValue
    storage = _assumeMainActor {
      let value = Storage(wrappedValue)
      if let scope = StateRuntime.scope {
        let key = scope.key()
        value.key = key
        value.box = scope.store.box(key, default: wrappedValue)
      }
      return value
    }
  }
  public init(initialValue: Value) { self.init(wrappedValue: initialValue) }
  public var wrappedValue: Value {
    get {
      let storage = self.storage
      return _assumeMainActor { let box = storage.registeredBox(); box.onRead?(); return box.value }
    }
    nonmutating set {
      let storage = self.storage
      nonisolated(unsafe) let newValue = newValue
      _assumeMainActor { storage.registeredBox().value = newValue }
    }
  }
  public var projectedValue: GestureState<Value> { self }
  @MainActor nonmutating func _reset() {
    // SwiftUI's GestureState resets to the value supplied at initialization.
    // The wrapper keeps that value in a separate slot so callback copies share
    // the same storage while reset remains deterministic.
    storage.box.value = storage.initialValue
  }
}

/// SwiftUI's toggle style family. The browser realizes the built-in looks from the
/// token each style reports through `_swiftUIWebToggleStyle` ("automatic", "switch",
/// "button", "checkbox").
@MainActor @preconcurrency public protocol ToggleStyle { nonisolated var _swiftUIWebToggleStyle: String { get } }
public extension ToggleStyle { nonisolated var _swiftUIWebToggleStyle: String { "automatic" } }
public nonisolated struct DefaultToggleStyle: ToggleStyle {
  public nonisolated init() {}
  public nonisolated var _swiftUIWebToggleStyle: String { "automatic" }
}
public nonisolated struct SwitchToggleStyle: ToggleStyle {
  public nonisolated init() {}
  public nonisolated var _swiftUIWebToggleStyle: String { "switch" }
}
public nonisolated struct ButtonToggleStyle: ToggleStyle {
  public nonisolated init() {}
  public nonisolated var _swiftUIWebToggleStyle: String { "button" }
}
public nonisolated struct CheckboxToggleStyle: ToggleStyle {
  public nonisolated init() {}
  public nonisolated var _swiftUIWebToggleStyle: String { "checkbox" }
}
public extension ToggleStyle where Self == DefaultToggleStyle {
  @MainActor @preconcurrency static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}
public extension ToggleStyle where Self == SwitchToggleStyle {
  static nonisolated var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}
public extension ToggleStyle where Self == ButtonToggleStyle {
  static nonisolated var button: ButtonToggleStyle { ButtonToggleStyle() }
}
public extension ToggleStyle where Self == CheckboxToggleStyle {
  static nonisolated var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}

/// SwiftUI's picker style family. Built-in styles report their token through
/// `_swiftUIWebPickerStyle`.
public protocol PickerStyle { var _swiftUIWebPickerStyle: String { get } }
public extension PickerStyle { var _swiftUIWebPickerStyle: String { "automatic" } }
public struct DefaultPickerStyle: PickerStyle {
  public init() {}
  public var _swiftUIWebPickerStyle: String { "automatic" }
}
public struct InlinePickerStyle: PickerStyle {
  public init() {}
  public var _swiftUIWebPickerStyle: String { "inline" }
}
public struct MenuPickerStyle: PickerStyle {
  public init() {}
  public var _swiftUIWebPickerStyle: String { "menu" }
}
public struct SegmentedPickerStyle: PickerStyle {
  public init() {}
  public var _swiftUIWebPickerStyle: String { "segmented" }
}
public struct NavigationLinkPickerStyle: PickerStyle {
  public init() {}
  public var _swiftUIWebPickerStyle: String { "navigation-link" }
}
public struct PalettePickerStyle: PickerStyle {
  public init() {}
  public var _swiftUIWebPickerStyle: String { "palette" }
}
public struct WheelPickerStyle: PickerStyle {
  public init() {}
  public var _swiftUIWebPickerStyle: String { "wheel" }
}
public extension PickerStyle where Self == DefaultPickerStyle { static var automatic: DefaultPickerStyle { DefaultPickerStyle() } }
public extension PickerStyle where Self == InlinePickerStyle { static var inline: InlinePickerStyle { InlinePickerStyle() } }
public extension PickerStyle where Self == MenuPickerStyle { static var menu: MenuPickerStyle { MenuPickerStyle() } }
public extension PickerStyle where Self == SegmentedPickerStyle { static var segmented: SegmentedPickerStyle { SegmentedPickerStyle() } }
public extension PickerStyle where Self == NavigationLinkPickerStyle { static var navigationLink: NavigationLinkPickerStyle { NavigationLinkPickerStyle() } }
public extension PickerStyle where Self == PalettePickerStyle { static var palette: PalettePickerStyle { PalettePickerStyle() } }
public extension PickerStyle where Self == WheelPickerStyle { static var wheel: WheelPickerStyle { WheelPickerStyle() } }

/// SwiftUI's text field style family.
public protocol TextFieldStyle { var _swiftUIWebTextFieldStyle: String { get } }
public extension TextFieldStyle { var _swiftUIWebTextFieldStyle: String { "automatic" } }
public struct DefaultTextFieldStyle: TextFieldStyle {
  public init() {}
  public var _swiftUIWebTextFieldStyle: String { "automatic" }
}
public struct PlainTextFieldStyle: TextFieldStyle {
  public init() {}
  public var _swiftUIWebTextFieldStyle: String { "plain" }
}
public struct RoundedBorderTextFieldStyle: TextFieldStyle {
  public init() {}
  public var _swiftUIWebTextFieldStyle: String { "rounded-border" }
}
public extension TextFieldStyle where Self == DefaultTextFieldStyle { static var automatic: DefaultTextFieldStyle { DefaultTextFieldStyle() } }
public extension TextFieldStyle where Self == PlainTextFieldStyle { static var plain: PlainTextFieldStyle { PlainTextFieldStyle() } }
public extension TextFieldStyle where Self == RoundedBorderTextFieldStyle { static var roundedBorder: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() } }

/// SwiftUI blend modes represented by CSS compositing operators in the web
/// host.  The semantic value remains backend-neutral for static/WASI output.
public enum BlendMode: Hashable, Sendable {
  case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn
  case softLight, hardLight, difference, exclusion, hue, saturation, color, luminosity
  case sourceAtop, destinationOver, destinationOut
  case plusDarker, plusLighter

  /// The CSS spelling of each case; SwiftUI does not expose a raw value. The Porter-Duff cases have no CSS
  /// `mix-blend-mode`; they keep their name here, and the renderer maps them to `normal` (see `_cssBlendMode`).
  package var rawValue: String {
    switch self {
    case .normal: "normal"
    case .multiply: "multiply"
    case .screen: "screen"
    case .overlay: "overlay"
    case .darken: "darken"
    case .lighten: "lighten"
    case .colorDodge: "colorDodge"
    case .colorBurn: "colorBurn"
    case .softLight: "softLight"
    case .hardLight: "hardLight"
    case .difference: "difference"
    case .exclusion: "exclusion"
    case .hue: "hue"
    case .saturation: "saturation"
    case .color: "color"
    case .luminosity: "luminosity"
    case .sourceAtop: "sourceAtop"
    case .destinationOver: "destinationOver"
    case .destinationOut: "destinationOut"
    case .plusDarker: "plusDarker"
    case .plusLighter: "plusLighter"
    }
  }
}

private let _scrollOwnerAttributes: Set<String> = [
  "data-scroll-position", "data-scroll-position-id", "data-scroll-position-anchor",
  "data-scroll-position-edge", "data-scroll-position-point", "data-scroll-position-mode",
  "data-scroll-position-initial-anchor", "data-default-scroll-anchor",
  "data-scroll-target-behavior", "data-scroll-disabled", "data-scroll-clip-disabled",
  "data-scroll-indicators", "data-scroll-bounce", "data-scroll-content-margins",
  "data-content-margins-placement"
]

private func _propagateScrollOwnerMetadata(
  _ node: _RenderNode,
  attributes: _NodeValues,
  styles: _NodeValues
) {
  let isScroll = node.attributes["data-scroll-node"] == "true" || node.classes.contains("scroll-view")
  if isScroll {
    for key in _scrollOwnerAttributes {
      if let value = attributes[key] { node.attributes[key] = value }
    }
    for key in ["overflow", "overscroll-behavior", "scrollbar-width"] {
      if let value = styles[key] { node.styles[key] = value }
    }
    return
  }
  for child in node.children { _propagateScrollOwnerMetadata(child, attributes: attributes, styles: styles) }
}

public nonisolated struct _SemanticCompatibilityModifier: ViewModifier {
  let attributes: _NodeValues
  let styles: _NodeValues
  /// Erased action content retained by the SwiftUI-shaped swipe modifier.
  /// Keeping this on the historical compatibility modifier avoids changing
  /// the public return type while still allowing action buttons to participate
  /// in normal Fiber identity and event dispatch.
  let swipeContent: (() -> AnyView)?
  /// Inherited control configuration (text-field/picker styles, hidden
  /// labels, hidden scroll content backgrounds). SwiftUI applies these
  /// modifiers to every matching control in the subtree, so they travel
  /// through the environment instead of only marking the modified node.
  let environment: ((inout EnvironmentValues) -> Void)?
  package init(
    attributes: _NodeValues = .init(),
    styles: _NodeValues = .init(),
    swipeContent: (() -> AnyView)? = nil,
    environment: ((inout EnvironmentValues) -> Void)? = nil
  ) {
    self.attributes = attributes
    self.styles = styles
    self.swipeContent = swipeContent
    self.environment = environment
  }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    if let environment { environment(&context.environment) }
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if attributes["data-layout-kind"] == "aspect" {
      // On a Group/ForEach the ratio applies to each element, as in SwiftUI.
      if node.kind == .fragment { for child in node.children where !child.isEmpty { _ = _semanticWrap(child, kind: "aspect") } }
      else { _ = _semanticWrap(node, kind: "aspect") }
    }
    if let swipeContent {
      let original = node.cloneSharingChildren()
      let renderedActions = swipeContent()._render(in: context.child(_FiberKey("swipe-actions")))
      let edge = attributes["data-swipe-edge"] ?? "trailing"
      let actions = _RenderNode.element("div")
      actions.classes = ["swipe-actions", "swipe-actions-\(edge)"]
      actions.attributes = [
        "data-swipe-action-edge": edge,
        "aria-hidden": "true",
        "role": "group",
        "aria-label": edge == "leading" ? "Leading actions" : "Trailing actions"
      ]
      if renderedActions.kind == .fragment {
        actions.children = renderedActions.children
      } else if !renderedActions.isEmpty {
        actions.children = [renderedActions]
      }

      // The content layer is the only element that moves while dragging.
      // Action buttons remain ordinary SwiftUI views with stable event IDs,
      // which is important when a virtualized row is recycled.
      let content = _RenderNode.element("div")
      content.classes = ["swipe-content"]
      content.attributes["data-swipe-content"] = "true"
      content.children = [original]

      node.kind = .element("div")
      node.text = nil
      node.attributes = attributes
      node.attributes["data-swipe-actions"] = "true"
      node.attributes["data-swipe-edge"] = edge
      node.attributes["data-swipe-full-swipe"] = attributes["data-swipe-full-swipe"] ?? "true"
      node.attributes["data-swipe-state"] = "closed"
      node.styles = styles
      node.classes = ["swipe-row"]
      node.children = edge == "leading" ? [actions, content] : [content, actions]
      node.events = .init()
      return
    }
    // Plain attributes and styles on a Group belong to each child, as in SwiftUI.
    node._forEachHost { node in
      for (key, value) in attributes { node.attributes[key] = value }
      // SwiftUI shadows what a view draws: for text that is its glyphs, not a box around it.
      let isText = node.kind == .text || node.attributes["data-layout-leaf"] == "text"
      for (key, value) in styles {
        if key == "box-shadow", !isText, let filter = _shapeShadowFilter(for: node, boxShadow: value) {
          node.styles["filter"] = filter
        } else if key == "box-shadow", !isText, node.styles["border-radius"] == nil, let radius = _wrappedClippedRadius(of: node) {
          // An overlay/background wrapper has the box of the clipped content it wraps, so its shadow
          // follows that content's rounded corners instead of a rectangle.
          node.styles["border-radius"] = radius
          node.styles[key] = value
        } else if key == "filter", let existing = node.styles["filter"], !existing.isEmpty, existing != "none" {
          // Filters chain, in the order of the modifiers (`.blur` then `.contrast` applies both), and a `colorMultiply`
          // before them keeps its place.
          node.styles["filter"] = existing + " " + value
        } else {
          node.styles[isText && key == "box-shadow" ? "text-shadow" : key] = value
        }
      }
      if attributes["data-allows-hit-testing"] != nil {
        _AccessibilityBackend.synchronizeHiddenHitTesting(on: node)
      }
      // Frame/padding modifiers often wrap a ScrollView. Keep scrolling
      // semantics on the actual native scroll owner as well as on the modifier
      // boundary, so browser coordinators never have to guess through wrappers.
      if attributes.keys.contains(where: _scrollOwnerAttributes.contains) {
        for child in node.children { _propagateScrollOwnerMetadata(child, attributes: attributes, styles: styles) }
      }
    }
  }
}

public extension Image {
  enum ResizingMode: Hashable, Sendable { case tile, stretch 
    /// The CSS spelling of each case; SwiftUI does not expose a raw value.
    var rawValue: String {
      switch self {
      case .tile: "tile"
      case .stretch: "stretch"
      }
    }
  }
  /// An `Image`, as in SwiftUI, so image-only modifiers (`interpolation`, `antialiased`) chain after it.
 func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: Image.ResizingMode = .stretch) -> Image {
    let resizing = _resizableModifier(capInsets: capInsets, resizingMode: resizingMode)
    var copy = self
    copy.imageAttributes.merge(resizing.attributes) { $1 }
    copy.imageStyles.merge(resizing.styles) { $1 }
    return copy
  }
  /// Images in the browser are scaled by the compositor, so only `.none` changes the result.
  func interpolation(_ interpolation: Image.Interpolation) -> Image {
    var copy = self
    copy.imageStyles["image-rendering"] = interpolation == .none ? "pixelated" : "auto"
    return copy
  }
}

// MARK: - Frequently used SwiftUI text and interaction modifiers

public extension View {

  nonisolated func underline(_ active: Bool = true, color: Color? = nil) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    var styles: _NodeValues = ["text-decoration-line": active ? "underline" : "none"]
    if let color { styles["text-decoration-color"] = color.cssValue }
    return modifier(_SemanticCompatibilityModifier(styles: styles))
  }
  @_disfavoredOverload nonisolated func tracking(_ value: Float) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { tracking(Double(value)) }
  nonisolated func tracking(_ value: Double) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_trackingModifier(value)) }
  nonisolated func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_toolbarModifier(visibility, for: bars)) }
  nonisolated func gesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View { modifier(GestureCompatibilityModifier(gesture: gesture, mask: mask)) }
}

package func _scrollDecodeID<ID: Hashable>(_ value: String, as: ID.Type) -> ID? {
  if ID.self == String.self { return value as? ID }
  if ID.self == Int.self { return Int(value) as? ID }
  if ID.self == UInt64.self { return UInt64(value) as? ID }
  if ID.self == Bool.self { return (value == "true") as? ID }
  return nil
}

package nonisolated struct GestureCompatibilityModifier: ViewModifier {
  public let name: String
  public let mask: GestureMask
  public let priority: String
  let gesture: _RendererGesture
  public init(name: String, mask: GestureMask) {
    self.name = name; self.mask = mask; self.priority = "normal"
    self.gesture = _assumeMainActor { _RendererGesture(name: name, spec: _GestureSpec(kind: name)) }
  }
  package init<G: Gesture>(gesture: G, mask: GestureMask, priority: String = "normal") {
    // SAFETY: gestures are only erased and read by the main-actor runtime; this entry point is nonisolated like SwiftUI's.
    nonisolated(unsafe) let gesture = gesture
    let erased = _assumeMainActor { gesture._makeRendererGesture() }
    self.name = erased.name; self.mask = mask; self.priority = priority; self.gesture = erased
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard mask != .none, context.environment.isEnabled else { return }
    // Group and TupleView flatten to _RenderNode fragments. A fragment has no
    // DOM host, so gesture metadata attached only to it disappears during
    // serialization. Mirror SwiftUI's transparent container behavior by
    // applying the gesture to each rendered child.
    if case .fragment = node.kind {
      for child in node.children { _apply(to: child, context: &context) }
      return
    }
    node.attributes["data-gesture"] = name
    node.attributes["data-gesture-mask"] = mask._swiftUIWebName
    node.attributes["data-gesture-priority"] = priority
    node.attributes["data-gesture-priorities"] = node.attributes["data-gesture-priorities"].map { "\($0),\(priority)" } ?? priority
    if priority == "simultaneous" { node.attributes["data-simultaneous-gesture"] = "true" }
    if priority == "high" { node.attributes["data-high-priority-gesture"] = "true" }
    if priority == "exclusive" { node.attributes["data-exclusive-gesture"] = "true" }
    let encodedDescriptor = gesture._swiftUIWebSpec.encoded
    node.attributes["data-gesture-descriptor"] = encodedDescriptor
    let descriptorList = node.attributes["data-gesture-descriptors"].map { "\($0)||\(encodedDescriptor)" } ?? encodedDescriptor
    node.attributes["data-gesture-descriptors"] = descriptorList
    node.attributes["data-gesture-coordinate-space"] = gesture._swiftUIWebSpec.coordinateSpace
    node.attributes["data-gesture-composition"] = gesture._swiftUIWebSpec.composition.rawValue
    // Composition descriptors can contain a transform gesture even though
    // their outer kind is `composition`; make sure the browser does not let
    // native pinch/rotate handling consume those pointers before our shared
    // recognizer sees them.
    let touchActionKind: String
    if gesture._swiftUIWebSpec.kind == "composition" {
      let encoded = gesture._swiftUIWebSpec.encoded
      // Avoid Foundation's locale-aware StringProtocol.contains overload in
      // the core modifier metadata path. That overload references
      // FoundationInternationalization/ICU even when no locale APIs are
      // used; this small stdlib-only scan preserves the same semantics.
      touchActionKind = _swiftUIWebContainsLiteral(encoded, "kind=magnify") || _swiftUIWebContainsLiteral(encoded, "kind=rotate") ? "transform" : _swiftUIWebContainsLiteral(encoded, "kind=drag") ? "drag" : "other"
    } else {
      touchActionKind = gesture._swiftUIWebSpec.kind
    }
    switch touchActionKind {
    case "magnify", "rotate", "transform": node.styles["touch-action"] = "none"
    case "drag": node.styles["touch-action"] = "pan-y"
    default: node.styles["touch-action"] = "manipulation"
    }
    let index = node.attributes["data-gesture-count"].flatMap(Int.init) ?? 0
    node.attributes["data-gesture-count"] = String(index + 1)
    let prefix = "gesture-\(gesture._swiftUIWebSpec.kind)-\(index)"
    node.attributes["data-gesture-event-prefix-\(index)"] = prefix
    if let changed = gesture.actionBox.changed { node.events["\(prefix)-changed"] = _EventHandler(name: "\(prefix)-changed", action: changed) }
    if let ended = gesture.actionBox.ended { node.events["\(prefix)-ended"] = _EventHandler(name: "\(prefix)-ended", action: { gesture.actionBox.endedAction?(); gesture.actionBox.reset?() }, valueAction: { raw in ended(raw); gesture.actionBox.reset?() }) }
    if let cancelled = gesture.actionBox.cancelled { node.events["\(prefix)-cancelled"] = _EventHandler(name: "\(prefix)-cancelled", action: { raw in cancelled(raw); gesture.actionBox.reset?() }) }
    else if gesture.actionBox.reset != nil { node.events["\(prefix)-cancelled"] = _EventHandler(name: "\(prefix)-cancelled", action: { raw in gesture.actionBox.reset?(); _ = raw }) }
    if gesture.actionBox.reset != nil && node.events["\(prefix)-ended"] == nil { node.events["\(prefix)-ended"] = _EventHandler(name: "\(prefix)-ended", action: { raw in gesture.actionBox.reset?(); _ = raw }) }
  }
}

func _swiftUIWebContainsLiteral(_ value: String, _ needle: String) -> Bool {
  guard !needle.isEmpty else { return true }
  var index = value.startIndex
  while index < value.endIndex {
    if value[index...].hasPrefix(needle) { return true }
    index = value.index(after: index)
  }
  return false
}

/// A small host-neutral long-press bridge. Browser hosts receive native
/// pointer events and can layer a timer on top of the semantic duration; the
/// Core fallback still provides correct pressing state and invokes the action
/// when the pointer is released. This is enough for SwiftUI controls that use
/// a zero-duration press to drive pressed-state styling.
package nonisolated struct LongPressCompatibilityModifier: ViewModifier {
  public let minimumDuration: Double
  public let maximumDistance: Double
  public let action: @MainActor () -> Void
  public let onPressingChanged: (@MainActor (Bool) -> Void)?

  public init(minimumDuration: Double = 0.5, maximumDistance: Double = 10, action: @escaping @MainActor () -> Void, onPressingChanged: (@MainActor (Bool) -> Void)? = nil) {
    self.minimumDuration = minimumDuration
    self.maximumDistance = maximumDistance
    self.action = action
    self.onPressingChanged = onPressingChanged
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-long-press"] = "true"
    node.attributes["data-long-press-duration"] = minimumDuration.clean
    node.attributes["data-long-press-distance"] = maximumDistance.clean
    guard context.environment.isEnabled else { return }
    // Keep the original pointer events as the deterministic static/WASI
    // fallback, while exposing separate semantic phases for a browser host
    // that can honor the duration and movement threshold.
    node.events["long-press-action"] = _EventHandler(name: "long-press-action", action: action)
    if let onPressingChanged {
      node.events["long-press-start"] = _EventHandler(name: "long-press-start", action: { onPressingChanged(true) })
      node.events["long-press-end"] = _EventHandler(name: "long-press-end", action: { onPressingChanged(false) })
      node.events["pointerdown"] = _EventHandler(name: "pointerdown", action: { onPressingChanged(true) })
      node.events["pointercancel"] = _EventHandler(name: "pointercancel", action: { onPressingChanged(false) })
      node.events["pointerup"] = _EventHandler(name: "pointerup", action: {
        onPressingChanged(false)
        action()
      })
    } else {
      node.events["pointerup"] = _EventHandler(name: "pointerup", action: action)
    }
  }
}

public extension View {
  // SwiftUIWeb's core stores layout measurements as Double.  WASI shims in
  // existing applications often expose SwiftUI's CGFloat as Float; these
  // overloads keep those sources source-compatible without changing the core
  // representation.
  @_disfavoredOverload nonisolated func frame(width: Float? = nil, height: Float? = nil, alignment: Alignment = .center) -> some View { frame(width: width.map(Double.init), height: height.map(Double.init), alignment: alignment) }
  @_disfavoredOverload nonisolated func frame(maxWidth: Float? = nil, maxHeight: Float? = nil, alignment: Alignment = .center) -> some View { frame(maxWidth: maxWidth.map(Double.init), maxHeight: maxHeight.map(Double.init), alignment: alignment) }
  @_disfavoredOverload nonisolated func frame(minWidth: Float? = nil, idealWidth: Float? = nil, maxWidth: Float? = nil, minHeight: Float? = nil, idealHeight: Float? = nil, maxHeight: Float? = nil, alignment: Alignment = .center) -> some View { frame(minWidth: minWidth.map(Double.init), idealWidth: idealWidth.map(Double.init), maxWidth: maxWidth.map(Double.init), minHeight: minHeight.map(Double.init), idealHeight: idealHeight.map(Double.init), maxHeight: maxHeight.map(Double.init), alignment: alignment) }
  @_disfavoredOverload nonisolated func padding(_ value: Float) -> some View { padding(Double(value)) }
  @_disfavoredOverload nonisolated func padding(_ edges: Edge.Set, _ length: Float? = nil) -> some View { padding(edges, length.map(Double.init)) }
  @_disfavoredOverload nonisolated func offset(x: Float = 0, y: Float = 0) -> some View { offset(x: Double(x), y: Double(y)) }
  @_disfavoredOverload nonisolated func opacity(_ value: Float) -> some View { opacity(Double(value)) }
  package nonisolated func _safeAreaPadding(_ edges: Edge.Set = .all, _ insets: EdgeInsets) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    var styles = _NodeValues()
    if edges.contains(.top) { styles["padding-top"] = "calc(env(safe-area-inset-top, 0px) + \(insets.top.clean)px)" }
    if edges.contains(.leading) { styles["padding-left"] = "calc(env(safe-area-inset-left, 0px) + \(insets.leading.clean)px)" }
    if edges.contains(.bottom) { styles["padding-bottom"] = "calc(env(safe-area-inset-bottom, 0px) + \(insets.bottom.clean)px)" }
    if edges.contains(.trailing) { styles["padding-right"] = "calc(env(safe-area-inset-right, 0px) + \(insets.trailing.clean)px)" }
    return modifier(_SemanticCompatibilityModifier(styles: styles))
  }
  nonisolated func blur(radius: Double, opaque: Bool = false) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_blurModifier(radius: radius))
  }
  nonisolated func mask<Mask: View>(alignment: Alignment = .center, @ViewBuilder _ mask: @escaping () -> Mask) -> some View {
    modifier(MaskCompatibilityModifier(mask: mask))
  }
}

package nonisolated struct ScrollVisibilityModifier: ViewModifier {
  public let threshold: Double
  fileprivate let action: (Bool) -> Void
  public init(threshold: Double = 0, action: @escaping (Bool) -> Void) {
    self.threshold = min(max(threshold, 0), 1)
    self.action = action
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-scroll-visibility"] = "true"
    node.attributes["data-scroll-visibility-threshold"] = threshold.clean
    // This is a host event rather than a DOM event.  Browser adapters can
    // connect the node to IntersectionObserver while static/WASI renderers
    // simply retain the source-compatible metadata.
    node.events["scrollVisibility"] = _EventHandler(name: "scrollVisibility", action: { raw in
      action(raw == "true")
    })
  }
}

/// Keeps a SwiftUI `scrollPosition(id:)` binding connected to rendered keyed
/// children. The core records the current target and anchor; browser hosts
/// can scroll that target into view after reconciliation without exposing DOM
/// objects or browser APIs to application code.
package nonisolated struct ScrollPositionModifier<ID: Hashable>: ViewModifier {
  fileprivate let binding: Binding<ID?>
  fileprivate let anchor: UnitPoint?

  public init(binding: Binding<ID?>, anchor: UnitPoint? = nil) {
    self.binding = binding
    self.anchor = anchor
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-scroll-position"] = "true"
    node.attributes["data-scroll-position-key"] = context._compactPathID + "#scroll-position"
    if let value = binding.wrappedValue {
      node.attributes["data-scroll-position-id"] = fiberKeyDescription(_FiberKey(value))
    } else {
      node.attributes.removeValue(forKey: "data-scroll-position-id")
    }
    if let anchor {
      node.attributes["data-scroll-position-anchor"] = "\(anchor.x.clean),\(anchor.y.clean)"
    }
    let binding = self.binding
    node.events["scrollPosition"] = _EventHandler(name: "scrollPosition", action: { raw in
      if let value = _scrollDecodeID(raw, as: ID.self) { binding.wrappedValue = value }
    })
    for child in node.children { _propagateScrollOwnerMetadata(child, attributes: node.attributes, styles: node.styles) }
  }
}

package nonisolated struct ScrollPositionValueModifier: ViewModifier {
  fileprivate let binding: Binding<ScrollPosition>
  fileprivate let anchor: UnitPoint?
  package init(binding: Binding<ScrollPosition>, anchor: UnitPoint?) {
    self.binding = binding
    self.anchor = anchor
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let position = binding.wrappedValue
    node.attributes["data-scroll-position"] = "true"
    node.attributes["data-scroll-position-mode"] = "value"
    node.attributes["data-scroll-position-key"] = context._compactPathID + "#scroll-position-value"
    if let id = position._idDescription { node.attributes["data-scroll-position-id"] = id }
    else { node.attributes.removeValue(forKey: "data-scroll-position-id") }
    if let edge = position.edge { node.attributes["data-scroll-position-edge"] = _scrollEdgeToken(edge) }
    else { node.attributes.removeValue(forKey: "data-scroll-position-edge") }
    // An empty component leaves that axis where it is (`scrollTo(x:)`).
    if position.point != nil || position.x != nil || position.y != nil {
      let x = position.point?.x ?? position.x
      let y = position.point?.y ?? position.y
      node.attributes["data-scroll-position-point"] = "\(x.map { Double($0).clean } ?? ""),\(y.map { Double($0).clean } ?? "")"
    } else {
      node.attributes.removeValue(forKey: "data-scroll-position-point")
    }
    if let anchor = position.anchor ?? anchor {
      node.attributes["data-scroll-position-anchor"] = "\(anchor.x.clean),\(anchor.y.clean)"
    }
    let initialAnchor = node.attributes["data-scroll-position-anchor"] ?? "0.5,0.5"
    node.attributes["data-scroll-position-initial-anchor"] = initialAnchor
    node.attributes["data-default-scroll-anchor"] = initialAnchor
    let binding = self.binding
    // The host reports only scrolls the user made. SwiftUI answers with a
    // position that is positioned by the user and names no target.
    node.events["scrollPositionUser"] = _EventHandler(name: "scrollPositionUser", action: { _ in
      var position = binding.wrappedValue
      position._setPositionedByUser()
      if position != binding.wrappedValue { binding.wrappedValue = position }
    })
    for child in node.children { _propagateScrollOwnerMetadata(child, attributes: node.attributes, styles: node.styles) }
  }
}

private func _scrollEdgeToken(_ edge: Edge) -> String {
  switch edge {
  case .top: "top"
  case .leading: "leading"
  case .bottom: "bottom"
  case .trailing: "trailing"
  }
}

package nonisolated struct MaskCompatibilityModifier<Mask: View>: ViewModifier {
  private let mask: () -> Mask
  public init(mask: @escaping () -> Mask) { self.mask = mask }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let maskNode = AnyView(mask())._render(in: context.child(_FiberKey("mask")))
    guard !maskNode.isEmpty else { return }
    let original = node.cloneSharingChildren()
    if let path = maskNode.attributes["data-shape-path"], !path.isEmpty {
      let maskURI = _svgMaskDataURI(path: path)
      original.styles["mask-image"] = "url(\"\(maskURI)\")"
      original.styles["-webkit-mask-image"] = "url(\"\(maskURI)\")"
      original.styles["mask-size"] = "100% 100%"
      original.styles["-webkit-mask-size"] = "100% 100%"
      original.styles["mask-repeat"] = "no-repeat"
      original.styles["-webkit-mask-repeat"] = "no-repeat"
    }
    node.kind = .element("div")
    node.text = nil
    node.attributes = ["data-mask": "true"]
    node.styles = ["overflow": "hidden", "position": "relative"]
    node.classes = ["mask-layer"]
    // The mask view remains in the semantic tree for accessibility and
    // reconciliation, but its pixels must not cover the masked content once
    // the CSS/SVG mask is active.
    if original.styles["mask-image"] != nil {
      maskNode.styles["display"] = "none"
      node.attributes["data-mask-backend"] = "svg"
    }
    node.children = [original, maskNode]
    node.events = .init()
  }
}

internal func _svgMaskDataURI(path: String, fillRule: String = "nonzero") -> String {
  let svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><path d='\(path)' fill='white' fill-rule='\(fillRule)'/></svg>"
  var encoded = _swiftUIWebReplacing(svg, "%", "%25")
  encoded = _swiftUIWebReplacing(encoded, "#", "%23")
  encoded = _swiftUIWebReplacing(encoded, "<", "%3C")
  encoded = _swiftUIWebReplacing(encoded, ">", "%3E")
  encoded = _swiftUIWebReplacing(encoded, "'", "%27")
  encoded = _swiftUIWebReplacing(encoded, "\"", "%22")
  encoded = _swiftUIWebReplacing(encoded, " ", "%20")
  return "data:image/svg+xml,\(encoded)"
}

@inline(__always)
private func _swiftUIWebReplacing(_ value: String, _ old: String, _ new: String) -> String {
  guard let oldCharacter = old.first, old.count == 1 else { return value }
  var result = ""
  result.reserveCapacity(value.utf8.count)
  for character in value {
    if character == oldCharacter {
      result.append(contentsOf: new)
    } else {
      result.append(character)
    }
  }
  return result
}

// Int64(exactly:) is nil, not a trap, for a whole value Int64 cannot hold (`.opacity(1e300)`).
private extension Double { var clean: String { Int64(exactly: self).map { String($0) } ?? String(self) } }
