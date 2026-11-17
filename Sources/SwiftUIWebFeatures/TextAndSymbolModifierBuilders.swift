@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

@inline(never)
func _truncationModeModifier(_ mode: Text.TruncationMode) -> _SemanticCompatibilityModifier {
  var styles: _NodeValues = ["text-overflow": "ellipsis"]
  if mode == .head { styles["direction"] = "rtl"; styles["unicode-bidi"] = "plaintext" }
  return _SemanticCompatibilityModifier(attributes: ["data-truncation-mode": mode.rawValue], styles: styles)
}

@inline(never)
func _textSelectionModifier(allowsSelection: Bool) -> _SemanticCompatibilityModifier {
  let userSelect = allowsSelection ? "text" : "none"
  return _SemanticCompatibilityModifier(styles: ["user-select": userSelect, "-webkit-user-select": userSelect])
}

@inline(never)
func _fontWidthModifier(_ width: Font.Width?) -> _SemanticCompatibilityModifier {
  return _SemanticCompatibilityModifier(styles: width.map { ["font-stretch": $0.rawValue] } ?? .init())
}

@inline(never)
func _allowsTighteningModifier(_ flag: Bool) -> _SemanticCompatibilityModifier {
  return _SemanticCompatibilityModifier(attributes: ["data-allows-tightening": flag ? "true" : "false"])
}

@inline(never)
func _imageScaleModifier(_ scale: Image.Scale) -> _SemanticCompatibilityModifier {
  let factor: String
  switch scale { case .small: factor = "0.78"; case .medium: factor = "1"; case .large: factor = "1.29" }
  return _SemanticCompatibilityModifier(attributes: ["data-image-scale": scale.rawValue], styles: ["--image-scale": factor])
}

@inline(never)
func _symbolRenderingModeModifier(_ mode: SymbolRenderingMode?) -> _SemanticCompatibilityModifier {
  return _SemanticCompatibilityModifier(attributes: ["data-symbol-rendering-mode": mode?.rawValue ?? "automatic"])
}

@inline(never)
func _symbolVariantModifier(_ variant: SymbolVariants) -> _SemanticCompatibilityModifier {
  return _SemanticCompatibilityModifier(attributes: ["data-symbol-variant": variant.rawValue])
}

@inline(never)
func _helpModifier(_ text: String) -> _SemanticCompatibilityModifier {
  return _SemanticCompatibilityModifier(attributes: ["title": text])
}

/// `privacySensitive()`: the attribute for styling, and the environment flag the text renderer reads.
package nonisolated struct _PrivacySensitiveModifier: ViewModifier {
  let sensitive: Bool
  @MainActor package func _modifyContext(_ context: inout _RenderContext) {
    context.environment._isPrivacySensitive = sensitive
  }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-privacy-sensitive"] = sensitive ? "true" : "false"
  }
}
