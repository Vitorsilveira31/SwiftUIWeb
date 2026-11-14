
/// Values that describe one phase of a custom hover effect. Effects are
/// evaluated for both phases when rendering; the host animates between the
/// resulting values without asking the Swift view tree to rerender.
@_spi(Renderer) public protocol HoverEffectContent {
  @_spi(Renderer) var _hoverEffectVisual: _HoverEffectVisual { get }
}

@_spi(Renderer) public struct EmptyHoverEffectContent: HoverEffectContent, Sendable {
  public init() {}
  @_spi(Renderer) public var _hoverEffectVisual: _HoverEffectVisual { _HoverEffectVisual() }
}

/// A compact, host-neutral set of visual properties supported by the browser
/// renderer for custom hover effects. The modifiers returned by
/// `HoverEffectContent` are this value, typed as `some HoverEffectContent`.
@_spi(Renderer) public struct _HoverEffectVisual: HoverEffectContent, Sendable {
  fileprivate var scaleX = 1.0
  fileprivate var scaleY = 1.0
  fileprivate var anchorX = 0.5
  fileprivate var anchorY = 0.5
  fileprivate var offsetX = 0.0
  fileprivate var offsetY = 0.0
  fileprivate var rotation = 0.0
  fileprivate var opacityValue = 1.0
  fileprivate var brightnessValue = 1.0
  fileprivate var blurValue = 0.0
  fileprivate var hasOpacity = false
  fileprivate var hasBrightness = false
  fileprivate var hasBlur = false
  fileprivate var saturationValue = 1.0
  fileprivate var contrastValue = 1.0
  fileprivate var hueRotationRadians = 0.0
  fileprivate var grayscaleValue = 0.0
  fileprivate var invertValue = 0.0
  fileprivate var hasExtraFilter = false
  fileprivate var animationCSS: String?

  public init() {}
  @_spi(Renderer) public var _hoverEffectVisual: _HoverEffectVisual { self }

  package func withScale(x: Double, y: Double, anchor: UnitPoint) -> _HoverEffectVisual {
    var result = self
    result.scaleX = x
    result.scaleY = y
    result.anchorX = anchor.x
    result.anchorY = anchor.y
    return result
  }

  func withOffset(x: Double, y: Double) -> _HoverEffectVisual {
    var result = self
    result.offsetX = x
    result.offsetY = y
    return result
  }

  package func withRotation(_ angle: Angle, anchor: UnitPoint) -> _HoverEffectVisual {
    var result = self
    result.rotation = angle.radians
    result.anchorX = anchor.x
    result.anchorY = anchor.y
    return result
  }

  func withOpacity(_ opacity: Double) -> _HoverEffectVisual {
    var result = self
    result.opacityValue = opacity
    result.hasOpacity = true
    return result
  }

  package func withBrightness(_ amount: Double) -> _HoverEffectVisual {
    var result = self
    result.brightnessValue = amount + 1
    result.hasBrightness = true
    return result
  }

  func withBlur(radius: Double) -> _HoverEffectVisual {
    var result = self
    result.blurValue = max(0, radius)
    result.hasBlur = true
    return result
  }

  package func withSaturation(_ amount: Double) -> _HoverEffectVisual {
    var result = self
    result.saturationValue = max(0, amount)
    result.hasExtraFilter = true
    return result
  }

  package func withContrast(_ amount: Double) -> _HoverEffectVisual {
    var result = self
    result.contrastValue = max(0, amount)
    result.hasExtraFilter = true
    return result
  }

  package func withHueRotation(_ angle: Angle) -> _HoverEffectVisual {
    var result = self
    result.hueRotationRadians = angle.radians
    result.hasExtraFilter = true
    return result
  }

  package func withGrayscale(_ amount: Double) -> _HoverEffectVisual {
    var result = self
    result.grayscaleValue = min(1, max(0, amount))
    result.hasExtraFilter = true
    return result
  }

  package func withColorInvert() -> _HoverEffectVisual {
    var result = self
    result.invertValue = 1
    result.hasExtraFilter = true
    return result
  }

  func animated(_ animation: Animation?) -> _HoverEffectVisual {
    var result = self
    result.animationCSS = animation?.cssValue
    return result
  }

  fileprivate var filterCSS: String {
    func clean(_ value: Double) -> String { value.isFinite ? String(value) : "0" }
    var css = "brightness(\(clean(brightnessValue))) blur(\(clean(blurValue))px)"
    if hasExtraFilter {
      css += " saturate(\(clean(saturationValue))) contrast(\(clean(contrastValue)))"
      css += " hue-rotate(\(clean(hueRotationRadians))rad) grayscale(\(clean(grayscaleValue))) invert(\(clean(invertValue)))"
    }
    return css
  }
}

@_spi(Renderer) public extension HoverEffectContent {

  func offset(x: CGFloat = 0, y: CGFloat = 0) -> some HoverEffectContent {
    _hoverEffectVisual.withOffset(x: x, y: y)
  }

  func opacity(_ opacity: Double) -> some HoverEffectContent { _hoverEffectVisual.withOpacity(opacity) }
  func blur(radius: Double) -> some HoverEffectContent { _hoverEffectVisual.withBlur(radius: radius) }

  func animation(
    _ animation: Animation?,
    body: (EmptyHoverEffectContent) -> some HoverEffectContent
  ) -> some HoverEffectContent {
    _combineHoverVisuals(_hoverEffectVisual, body(EmptyHoverEffectContent())._hoverEffectVisual)
      .animated(animation)
  }
}

/// A custom hover effect. Built-in effects (`.automatic`, `.highlight`,
/// `.lift`, `.empty`) are leaf values with `Body == Never`; custom effects
/// compose a `body(content:)`.
public protocol CustomHoverEffect {
  associatedtype Body: CustomHoverEffect
  typealias Content = EmptyHoverEffect

  func body(content: Self.Content) -> Self.Body

  /// Underscored renderer hooks; not SwiftUI API.
  var _hoverEffectStyle: String? { get }
  @_spi(Renderer) var _hoverEffectGroup: HoverEffectGroup? { get }
  var _isHoverEffectDisabled: Bool { get }
  @_spi(Renderer) func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual
}

public extension CustomHoverEffect {
  @_spi(Renderer) func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual {
    body(content: EmptyHoverEffect())._hoverEffectVisual(isActive: isActive, proxy: proxy)
  }

  var _hoverEffectStyle: String? { nil }
  @_spi(Renderer) var _hoverEffectGroup: HoverEffectGroup? { nil }
  var _isHoverEffectDisabled: Bool { false }

}

public extension CustomHoverEffect where Body == Never {
  func body(content: Self.Content) -> Never {
    fatalError("A leaf hover effect has no body")
  }
}

extension Never: CustomHoverEffect {}

public extension CustomHoverEffect where Self == AutomaticHoverEffect {
  static nonisolated var automatic: AutomaticHoverEffect { AutomaticHoverEffect() }
}

/// The built-in automatic effect: the host picks the treatment for the control.
public struct AutomaticHoverEffect: CustomHoverEffect {
  public typealias Body = Never
  public init() {}
  public var _hoverEffectStyle: String? { "automatic" }
  @_spi(Renderer) public func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual { _HoverEffectVisual() }
}

/// The built-in highlight effect.
public struct HighlightHoverEffect: CustomHoverEffect {
  public typealias Body = Never
  public init() {}
  public var _hoverEffectStyle: String? { "highlight" }
  @_spi(Renderer) public func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual { _HoverEffectVisual() }
}

/// The built-in lift effect.
public struct LiftHoverEffect: CustomHoverEffect {
  public typealias Body = Never
  public init() {}
  public var _hoverEffectStyle: String? { "lift" }
  @_spi(Renderer) public func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual { _HoverEffectVisual() }
}

/// The base custom effect used by `CustomHoverEffect.body(content:)`.
public struct EmptyHoverEffect: CustomHoverEffect {
  public typealias Body = Never
  init() {}
  public var _hoverEffectStyle: String? { "empty" }
  @_spi(Renderer) public func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual { _HoverEffectVisual() }
}

/// A type-erased SwiftUI `HoverEffect`: any custom effect, plus the built-in
/// `automatic`, `highlight` and `lift` values.
public struct HoverEffect: CustomHoverEffect, @unchecked Sendable {
  public typealias Body = Never

  private let styleName: String?
  private let effectGroup: HoverEffectGroup?
  private let effectDisabled: Bool
  private let visual: (Bool, GeometryProxy) -> _HoverEffectVisual

  public init<E: CustomHoverEffect>(_ effect: E) {
    styleName = effect._hoverEffectStyle
    effectGroup = effect._hoverEffectGroup
    effectDisabled = effect._isHoverEffectDisabled
    visual = { isActive, proxy in effect._hoverEffectVisual(isActive: isActive, proxy: proxy) }
  }

  public static var automatic: HoverEffect { HoverEffect(AutomaticHoverEffect()) }
  public static var highlight: HoverEffect { HoverEffect(HighlightHoverEffect()) }
  public static var lift: HoverEffect { HoverEffect(LiftHoverEffect()) }

  public var _hoverEffectStyle: String? { styleName }
  @_spi(Renderer) public var _hoverEffectGroup: HoverEffectGroup? { effectGroup }
  public var _isHoverEffectDisabled: Bool { effectDisabled }
  @_spi(Renderer) public func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual {
    visual(isActive, proxy)
  }
}

/// A custom effect described by a phase-aware closure.
@_spi(Renderer) public struct ContentHoverEffect<Effect: HoverEffectContent>: CustomHoverEffect {
  public let group: HoverEffectGroup?
  public let isEnabled: Bool
  private let contentBody: (EmptyHoverEffectContent, Bool, GeometryProxy) -> Effect

  public init(
    group: HoverEffectGroup? = nil,
    isEnabled: Bool = true,
    body: @escaping (EmptyHoverEffectContent, Bool, GeometryProxy) -> Effect
  ) {
    self.group = group
    self.isEnabled = isEnabled
    contentBody = body
  }

  public typealias Body = ContentHoverEffect<Effect>
  public func body(content: EmptyHoverEffect) -> Body { self }
  @_spi(Renderer) public var _hoverEffectGroup: HoverEffectGroup? { group }
  public var _isHoverEffectDisabled: Bool { !isEnabled }

  @_spi(Renderer) public func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual {
    contentBody(EmptyHoverEffectContent(), isActive && isEnabled, proxy)._hoverEffectVisual
  }
}

/// A namespace token gives named effect groups a stable identity across
/// reevaluations of a SwiftUI-shaped view value.
@propertyWrapper
public struct Namespace: DynamicProperty {
  @State private var token: _HoverNamespaceToken

  public init() { _token = State(wrappedValue: _HoverNamespaceToken()) }
  public var wrappedValue: ID { ID(token: token) }

  public struct ID: Hashable, Sendable {
    private let token: ObjectIdentifier
    fileprivate init(token: _HoverNamespaceToken) { self.token = ObjectIdentifier(token) }
    // Embedded Swift does not provide `String(describing:)`. The token's address is unique among live namespaces and
    // stable for the token's lifetime, the period during which a hover group needs to match across renders; a 32-bit
    // hash of it could name two namespaces alike.
    package var _stableIdentity: String { String(UInt(bitPattern: token)) }
  }
}

private final class _HoverNamespaceToken {}

/// Identifies hover effects that should activate in concert.
@_spi(Renderer) public struct HoverEffectGroup: Hashable, Sendable {
  public struct Behavior: Hashable, Sendable {
    package let rawValue: String
    private init(_ rawValue: String) { self.rawValue = rawValue }
    public static let activatesGroup = Behavior("activatesGroup")
    public static let preservesGroup = Behavior("preservesGroup")
  }

  package let id: String
  package let behavior: Behavior

  package init(id: String, behavior: Behavior = .activatesGroup) {
    self.id = id
    self.behavior = behavior
  }

  public init(_ namespace: Namespace.ID, behavior: Behavior = .activatesGroup) {
    self.init(id: namespace._stableIdentity, behavior: behavior)
  }

  public init(id: String?, in namespace: Namespace.ID, behavior: Behavior = .activatesGroup) {
    self.init(id: "\(namespace._stableIdentity):\(id ?? "")", behavior: behavior)
  }

  public static let systemOverlays = HoverEffectGroup(id: "system-overlays")
}

package func _combineHoverVisuals(_ first: _HoverEffectVisual, _ second: _HoverEffectVisual) -> _HoverEffectVisual {
  var result = first
  result.scaleX *= second.scaleX
  result.scaleY *= second.scaleY
  result.offsetX += second.offsetX
  result.offsetY += second.offsetY
  result.rotation += second.rotation
  if second.hasOpacity { result.opacityValue *= second.opacityValue; result.hasOpacity = true }
  if second.hasBrightness { result.brightnessValue *= second.brightnessValue; result.hasBrightness = true }
  if second.hasBlur { result.blurValue += second.blurValue; result.hasBlur = true }
  result.animationCSS = second.animationCSS ?? first.animationCSS
  return result
}

package nonisolated struct HoverEffectModifier<Effect: CustomHoverEffect>: ViewModifier {
  package let effect: Effect
  package let group: HoverEffectGroup?
  package let isEnabled: Bool

  package init(effect: Effect, group: HoverEffectGroup? = nil, isEnabled: Bool = true) {
    self.effect = effect
    self.group = group
    self.isEnabled = isEnabled
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    _applyHoverEffect(
      effect,
      to: node,
      group: group,
      enabled: isEnabled && context.environment.isHoverEffectEnabled,
      context: context
    )
  }
}

package nonisolated struct DefaultHoverEffectModifier: ViewModifier {
  package let effect: HoverEffect
  package init(effect: HoverEffect) { self.effect = effect }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    context.environment.defaultHoverEffect = effect
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard context.environment.isHoverEffectEnabled else { return }
    _applyDefaultHoverEffect(effect, to: node, context: context)
  }
}

package nonisolated struct HoverEffectDisabledModifier: ViewModifier {
  package let disabled: Bool
  package init(disabled: Bool) { self.disabled = disabled }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    context.environment.isHoverEffectEnabled = context.environment.isHoverEffectEnabled && !disabled
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if !context.environment.isHoverEffectEnabled { node.attributes["data-hover-disabled"] = "true" }
  }
}

package nonisolated struct HoverEffectGroupModifier: ViewModifier {
  package let group: HoverEffectGroup?
  package let implicit: Bool
  package init(group: HoverEffectGroup?, implicit: Bool = false) {
    self.group = group
    self.implicit = implicit
  }

  @MainActor private func resolvedGroup(_ context: _RenderContext) -> HoverEffectGroup? {
    if let group { return group }
    guard implicit else { return nil }
    return HoverEffectGroup(id: "implicit:\(context._compactPathID)")
  }

  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    context.environment._hoverEffectGroup = resolvedGroup(context)
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard let group = resolvedGroup(context) else { return }
    node.attributes["data-hover-group-root"] = group.id
    node.attributes["data-hover-group-behavior"] = group.behavior.rawValue
  }
}

package nonisolated struct ListRowHoverEffectModifier: ViewModifier {
  package let effect: HoverEffect?
  package init(effect: HoverEffect?) { self.effect = effect }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard let effect else { return }
    node.attributes["data-list-row-hover-effect"] = effect._hoverEffectStyle ?? "custom"
  }
}

package nonisolated struct ListRowHoverEffectDisabledModifier: ViewModifier {
  package let disabled: Bool
  package init(disabled: Bool) { self.disabled = disabled }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if disabled { node.attributes["data-list-row-hover-disabled"] = "true" }
  }
}

@MainActor private func _applyHoverEffect<Effect: CustomHoverEffect>(
  _ effect: Effect,
  to node: _RenderNode,
  group explicitGroup: HoverEffectGroup?,
  enabled requestedEnabled: Bool,
  context: _RenderContext,
  source: String = "explicit"
) {
  let enabled = requestedEnabled && !effect._isHoverEffectDisabled
  let style = effect._hoverEffectStyle ?? "custom"
  node.attributes["data-hover-effect"] = style
  node.attributes["data-hover-enabled"] = enabled ? "true" : "false"
  node.attributes["data-hover-source"] = source
  if let group = effect._hoverEffectGroup ?? explicitGroup ?? context.environment._hoverEffectGroup {
    node.attributes["data-hover-group"] = group.id
    node.attributes["data-hover-group-behavior"] = group.behavior.rawValue
  }
  let proxy = _hoverGeometryProxy(node)
  let inactive = effect._hoverEffectVisual(isActive: false, proxy: proxy)
  let active = effect._hoverEffectVisual(isActive: enabled, proxy: proxy)
  _writeHoverValues(inactive, active: active, to: node)
}

@MainActor private func _applyDefaultHoverEffect(_ effect: HoverEffect, to node: _RenderNode, context: _RenderContext) {
  if _isHoverEligible(node), node.attributes["data-hover-effect"] == nil,
     node.attributes["disabled"] == nil, node.attributes["aria-disabled"] != "true" {
    _applyHoverEffect(effect, to: node, group: nil, enabled: true, context: context, source: "default")
  }
  for child in node.children { _applyDefaultHoverEffect(effect, to: child, context: context) }
}

private func _isHoverEligible(_ node: _RenderNode) -> Bool {
  if !node.events.isEmpty { return true }
  guard case .element(let tag) = node.kind else { return false }
  return tag == "button" || tag == "a" || tag == "input" || tag == "select" || tag == "textarea"
}

private func _hoverGeometryProxy(_ node: _RenderNode) -> GeometryProxy {
  let width = _hoverPixelDimension(node.styles["width"])
  let height = _hoverPixelDimension(node.styles["height"])
  return GeometryProxy(size: CGSize(width: width, height: height))
}

private func _hoverPixelDimension(_ value: String?) -> Double {
  guard let value, value.hasSuffix("px"), let number = Double(value.dropLast(2)), number.isFinite else { return 0 }
  return number
}

private func _writeHoverValues(_ inactive: _HoverEffectVisual, active: _HoverEffectVisual, to node: _RenderNode) {
  func clean(_ value: Double) -> String { value.isFinite ? String(value) : "0" }
  node.styles["--hover-rest-scale"] = "\(clean(inactive.scaleX)) \(clean(inactive.scaleY))"
  node.styles["--hover-active-scale"] = "\(clean(active.scaleX)) \(clean(active.scaleY))"
  node.styles["--hover-rest-translate"] = "\(clean(inactive.offsetX))px \(clean(inactive.offsetY))px"
  node.styles["--hover-active-translate"] = "\(clean(active.offsetX))px \(clean(active.offsetY))px"
  node.styles["--hover-rest-rotate"] = "\(clean(inactive.rotation))rad"
  node.styles["--hover-active-rotate"] = "\(clean(active.rotation))rad"
  node.styles["--hover-rest-origin"] = "\(clean(inactive.anchorX * 100))% \(clean(inactive.anchorY * 100))%"
  node.styles["--hover-active-origin"] = "\(clean(active.anchorX * 100))% \(clean(active.anchorY * 100))%"
  if inactive.hasOpacity || active.hasOpacity {
    node.attributes["data-hover-has-opacity"] = "true"
    node.styles["--hover-rest-opacity"] = clean(inactive.opacityValue)
    node.styles["--hover-active-opacity"] = clean(active.opacityValue)
  }
  if inactive.hasBrightness || active.hasBrightness || inactive.hasBlur || active.hasBlur
      || inactive.hasExtraFilter || active.hasExtraFilter {
    node.attributes["data-hover-has-filter"] = "true"
    node.styles["--hover-rest-filter"] = inactive.filterCSS
    node.styles["--hover-active-filter"] = active.filterCSS
  }
  if let animation = active.animationCSS ?? inactive.animationCSS,
     let (duration, timing) = _hoverAnimationParts(animation) {
    node.styles["--hover-duration"] = duration
    node.styles["--hover-timing"] = timing
  }
}

private func _hoverAnimationParts(_ css: String) -> (String, String)? {
  let components = css.split(whereSeparator: { $0 == " " || $0 == "\t" })
  guard let duration = components.first(where: { $0.hasSuffix("ms") || $0.hasSuffix("s") }),
        let timing = components.last,
        timing != duration else { return nil }
  return (String(duration), String(timing))
}
