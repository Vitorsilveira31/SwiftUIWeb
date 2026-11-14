@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

@_spi(Renderer) public extension HoverEffectContent {
  func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some HoverEffectContent {
    _hoverEffectVisual.withScale(x: scale.width, y: scale.height, anchor: anchor)
  }

  func scaleEffect(_ scale: CGFloat, anchor: UnitPoint = .center) -> some HoverEffectContent {
    _hoverEffectVisual.withScale(x: scale, y: scale, anchor: anchor)
  }

  func scaleEffect(x: CGFloat = 1.0, y: CGFloat = 1.0, anchor: UnitPoint = .center) -> some HoverEffectContent {
    _hoverEffectVisual.withScale(x: x, y: y, anchor: anchor)
  }

  func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some HoverEffectContent {
    _hoverEffectVisual.withRotation(angle, anchor: anchor)
  }

  func brightness(_ amount: Double) -> some HoverEffectContent { _hoverEffectVisual.withBrightness(amount) }

  func saturation(_ amount: Double) -> some HoverEffectContent { _hoverEffectVisual.withSaturation(amount) }

  func contrast(_ amount: Double) -> some HoverEffectContent { _hoverEffectVisual.withContrast(amount) }

  func hueRotation(_ angle: Angle) -> some HoverEffectContent { _hoverEffectVisual.withHueRotation(angle) }

  func grayscale(_ amount: Double) -> some HoverEffectContent { _hoverEffectVisual.withGrayscale(amount) }

  func colorInvert() -> some HoverEffectContent { _hoverEffectVisual.withColorInvert() }
}

public extension CustomHoverEffect {
  @_spi(Renderer) func hoverEffect<Effect: CustomHoverEffect>(
    _ effect: Effect,
    in group: HoverEffectGroup? = nil,
    isEnabled: Bool = true
  ) -> some CustomHoverEffect {
    CombinedHoverEffect(primary: self, secondary: effect, group: group, isEnabled: isEnabled)
  }

  func hoverEffectDisabled(_ isDisabled: Bool = true) -> some CustomHoverEffect {
    DisabledHoverEffect(effect: self, disabled: isDisabled)
  }

  @_spi(Renderer) func hoverEffectGroup(_ group: HoverEffectGroup?) -> some CustomHoverEffect {
    GroupedHoverEffect(effect: self, group: group)
  }

  @_spi(Renderer) func hoverEffectGroup(
    id: String? = nil,
    in namespace: Namespace.ID,
    behavior: HoverEffectGroup.Behavior = .activatesGroup
  ) -> some CustomHoverEffect {
    hoverEffectGroup(HoverEffectGroup(id: id, in: namespace, behavior: behavior))
  }
}

public extension CustomHoverEffect where Self == HighlightHoverEffect {
  static var highlight: HighlightHoverEffect { HighlightHoverEffect() }
}

public extension CustomHoverEffect where Self == LiftHoverEffect {
  static var lift: LiftHoverEffect { LiftHoverEffect() }
}

/// An effect value that activates a previously declared group.
@_spi(Renderer) public struct GroupHoverEffect: CustomHoverEffect {
  public let group: HoverEffectGroup?
  package init(_ group: HoverEffectGroup?) { self.group = group }
  public typealias Body = GroupHoverEffect
  public func body(content: EmptyHoverEffect) -> GroupHoverEffect { self }
  @_spi(Renderer) public var _hoverEffectGroup: HoverEffectGroup? { group }
  public var _hoverEffectStyle: String? { "empty" }
  @_spi(Renderer) public func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual {
    _HoverEffectVisual()
  }
}

@_spi(Renderer) public extension CustomHoverEffect where Self == GroupHoverEffect {
  static func hoverEffectGroup(
    id: String? = nil,
    in namespace: Namespace.ID,
    behavior: HoverEffectGroup.Behavior = .activatesGroup
  ) -> GroupHoverEffect {
    GroupHoverEffect(HoverEffectGroup(id: id, in: namespace, behavior: behavior))
  }
}

@_spi(Renderer) public extension EmptyHoverEffect {
  func hoverEffect<Effect: HoverEffectContent>(
    in group: HoverEffectGroup? = nil,
    isEnabled: Bool = true,
    body: @escaping (EmptyHoverEffectContent, Bool, GeometryProxy) -> Effect
  ) -> ContentHoverEffect<Effect> {
    ContentHoverEffect(group: group, isEnabled: isEnabled, body: body)
  }
}

package struct CombinedHoverEffect<Primary: CustomHoverEffect, Secondary: CustomHoverEffect>: CustomHoverEffect {
  package let primary: Primary
  package let secondary: Secondary
  package let group: HoverEffectGroup?
  package let isEnabled: Bool
  public typealias Body = CombinedHoverEffect<Primary, Secondary>

  init(primary: Primary, secondary: Secondary, group: HoverEffectGroup?, isEnabled: Bool) {
    self.primary = primary
    self.secondary = secondary
    self.group = group
    self.isEnabled = isEnabled
  }

  public func body(content: EmptyHoverEffect) -> Body { self }
  public var _hoverEffectStyle: String? { primary._hoverEffectStyle ?? secondary._hoverEffectStyle }
  @_spi(Renderer) public var _hoverEffectGroup: HoverEffectGroup? { group ?? primary._hoverEffectGroup ?? secondary._hoverEffectGroup }
  public var _isHoverEffectDisabled: Bool {
    !isEnabled || primary._isHoverEffectDisabled || secondary._isHoverEffectDisabled
  }

  @_spi(Renderer) public func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual {
    let active = isActive && !_isHoverEffectDisabled
    return _combineHoverVisuals(
      primary._hoverEffectVisual(isActive: active, proxy: proxy),
      secondary._hoverEffectVisual(isActive: active, proxy: proxy)
    )
  }
}

package struct DisabledHoverEffect<Effect: CustomHoverEffect>: CustomHoverEffect {
  package let effect: Effect
  package let disabled: Bool
  public typealias Body = DisabledHoverEffect<Effect>
  init(effect: Effect, disabled: Bool) { self.effect = effect; self.disabled = disabled }
  public func body(content: EmptyHoverEffect) -> Body { self }
  public var _hoverEffectStyle: String? { effect._hoverEffectStyle }
  @_spi(Renderer) public var _hoverEffectGroup: HoverEffectGroup? { effect._hoverEffectGroup }
  public var _isHoverEffectDisabled: Bool { disabled || effect._isHoverEffectDisabled }
  @_spi(Renderer) public func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual {
    effect._hoverEffectVisual(isActive: isActive && !disabled, proxy: proxy)
  }
}

package struct GroupedHoverEffect<Effect: CustomHoverEffect>: CustomHoverEffect {
  package let effect: Effect
  package let group: HoverEffectGroup?
  public typealias Body = GroupedHoverEffect<Effect>
  init(effect: Effect, group: HoverEffectGroup?) { self.effect = effect; self.group = group }
  public func body(content: EmptyHoverEffect) -> Body { self }
  public var _hoverEffectStyle: String? { effect._hoverEffectStyle }
  @_spi(Renderer) public var _hoverEffectGroup: HoverEffectGroup? { group ?? effect._hoverEffectGroup }
  public var _isHoverEffectDisabled: Bool { effect._isHoverEffectDisabled }
  @_spi(Renderer) public func _hoverEffectVisual(isActive: Bool, proxy: GeometryProxy) -> _HoverEffectVisual {
    effect._hoverEffectVisual(isActive: isActive, proxy: proxy)
  }
}
