@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

/// A shadow length in whole CSS pixels. A non-finite value is 0, and the magnitude is capped so `Int(_:)` cannot trap
/// on wasm32 (where `Int` is 32 bits).
private func _hoverPixels(_ value: Double) -> Int {
  guard value.isFinite else { return 0 }
  return Int(Swift.max(-1e9, Swift.min(1e9, value.rounded())))
}
/// Renderer-level description of hover feedback the browser applies itself.
///
/// Applications do not call these: they write standard SwiftUI
/// (`@State` + `onHover`, `hoverEffect`) and the framework learns the hovered
/// look and emits the same kind of rule (see HoverAssign.swift). These modifiers
/// stay as an SPI for the pieces of the renderer that describe a hover directly.
/// They record two values in CSS custom properties and mark the element, and
/// the stylesheet SwiftUIWeb ships applies them with `:hover`, so nothing runs
/// in Swift while the pointer moves.
///
/// The rules live in the `components` cascade layer of the framework
/// stylesheet, so any unlayered CSS an app adds overrides them without
/// `!important`. The attribute and property names below are the contract:
/// `[data-hover-bg]`, `--hover-bg-base`, `--hover-bg`, and so on.
@_spi(Renderer) public nonisolated struct _WebHoverModifier: ViewModifier {
  public let attributes: [String: String]
  public let styles: [String: String]
  public init(attributes: [String: String], styles: [String: String] = [:]) {
    self.attributes = attributes
    self.styles = styles
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    for (key, value) in attributes { node.attributes[key] = value }
    for (key, value) in styles { node.styles[key] = value }
  }
}

@_spi(Renderer) public extension View {
  /// Background that changes to `hover` while the pointer is over the view.
  nonisolated func webHoverBackground(_ base: Color, hover: Color) -> some View {
    _modified(_WebHoverModifier(
      attributes: ["data-hover-bg": ""],
      styles: ["--hover-bg-base": base.cssValue, "--hover-bg": hover.cssValue]
    ))
  }

  /// Text and icon color that changes to `hover` while the pointer is over the view.
  nonisolated func webHoverForeground(_ base: Color, hover: Color) -> some View {
    _modified(_WebHoverModifier(
      attributes: ["data-hover-fg": ""],
      styles: ["--hover-fg-base": base.cssValue, "--hover-fg": hover.cssValue]
    ))
  }

  /// Underlines the text inside the view while the pointer is over it.
  nonisolated func webHoverUnderline() -> some View {
    _modified(_WebHoverModifier(attributes: ["data-hover-underline": ""]))
  }

  /// Soft shadow shown while the pointer is over the view.
  nonisolated func webHoverShadow(_ color: Color, radius: Double, y: Double) -> some View {
    _modified(_WebHoverModifier(
      attributes: ["data-hover-shadow": ""],
      styles: [
        "--hover-shadow-color": color.cssValue,
        "--hover-shadow-blur": "\(_hoverPixels(radius * 2))px",
        "--hover-shadow-y": "\(_hoverPixels(y))px"
      ]
    ))
  }

  /// Makes shapes inside this view read their stroke color from
  /// `Color.webHoverStroke(fallback:)`, which switches to `hover` under the pointer.
  nonisolated func webHoverStroke(base: Color, hover: Color) -> some View {
    _modified(_WebHoverModifier(
      attributes: ["data-hover-stroke": ""],
      styles: ["--hover-stroke-base": base.cssValue, "--hover-stroke-hover": hover.cssValue]
    ))
  }

  /// Marks the view whose hover raises the descendants marked `webLiftedByHover(shadow:)`.
  nonisolated func webHoverLiftsChildren() -> some View {
    _modified(_WebHoverModifier(attributes: ["data-hover-lifts": ""]))
  }

  /// Raised by 3 points with a soft shadow while an ancestor marked
  /// `webHoverLiftsChildren()` is hovered.
  nonisolated func webLiftedByHover(shadow: Color) -> some View {
    _modified(_WebHoverModifier(
      attributes: ["data-lift-target": ""],
      styles: ["--hover-lift-shadow": shadow.cssValue]
    ))
  }
}

@_spi(Renderer) public extension Color {
  /// Stroke color that follows the nearest `webHoverStroke(base:hover:)` ancestor
  /// and is `fallback` outside of one.
  static func webHoverStroke(fallback: Color) -> Color {
    Color("var(--hover-stroke, \(fallback.cssValue))")
  }
}
