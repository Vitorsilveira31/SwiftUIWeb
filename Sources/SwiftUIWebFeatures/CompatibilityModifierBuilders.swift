@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

@inline(never)
func _aspectRatioModifier(_ aspectRatio: Double?, contentMode: ContentMode) -> _SemanticCompatibilityModifier {
  var styles: _NodeValues = ["object-fit": contentMode == .fill ? "cover" : "contain"]
  if let aspectRatio, aspectRatio > 0 { styles["aspect-ratio"] = String(aspectRatio) }
  return _SemanticCompatibilityModifier(attributes: ["data-layout-kind": "aspect", "data-aspect-ratio": aspectRatio.map { String($0) } ?? "", "data-aspect-fill": String(contentMode == .fill)], styles: styles)
}

@inline(never)
func _scaleEffectModifier(_ scale: Double, anchor: UnitPoint) -> _SemanticCompatibilityModifier {
  return _SemanticCompatibilityModifier(styles: ["transform": "scale(\(scale))", "transform-origin": "\(anchor.x * 100)% \(anchor.y * 100)%"])
}

@inline(never)
func _scaleEffectModifier(x: Double, y: Double, anchor: UnitPoint) -> _SemanticCompatibilityModifier {
  return _SemanticCompatibilityModifier(styles: ["transform": "scale(\(x), \(y))", "transform-origin": "\(anchor.x * 100)% \(anchor.y * 100)%"])
}

@inline(never)
func _rotationEffectModifier(_ angle: Angle, anchor: UnitPoint) -> _SemanticCompatibilityModifier {
  return _SemanticCompatibilityModifier(styles: ["transform": "rotate(\(angle.radians)rad)", "transform-origin": "\(anchor.x * 100)% \(anchor.y * 100)%"])
}

@inline(never)
func _rotation3DEffectModifier(_ angle: Angle, axis: (x: Double, y: Double, z: Double), anchor: UnitPoint, anchorZ: Double) -> _SemanticCompatibilityModifier {
  return _SemanticCompatibilityModifier(attributes: ["data-rotation3d-axis": "\(axis.x),\(axis.y),\(axis.z)"], styles: ["transform": "rotate3d(\(axis.x), \(axis.y), \(axis.z), \(angle.radians)rad)", "transform-origin": "\(anchor.x * 100)% \(anchor.y * 100)% \(anchorZ)px"])
}

@inline(never)
func _rotation3DEffectModifier(_ angle: Angle, axis: (x: Double, y: Double, z: Double), anchor: UnitPoint, anchorZ: Double, perspective: Double) -> _SemanticCompatibilityModifier {
  return _SemanticCompatibilityModifier(
    attributes: ["data-rotation3d-axis": "\(axis.x),\(axis.y),\(axis.z)", "data-rotation3d-perspective": String(perspective)],
    styles: ["transform": "perspective(\(perspective == 0 ? 0 : (1 / perspective * 1000))px) rotate3d(\(axis.x), \(axis.y), \(axis.z), \(angle.radians)rad)", "transform-origin": "\(anchor.x * 100)% \(anchor.y * 100)% \(anchorZ)px"]
  )
}

@inline(never)
func _brightnessModifier(_ amount: Double) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-brightness": String(amount)], styles: ["filter": "brightness(\(1 + amount))"])
}

@inline(never)
func _contrastModifier(_ amount: Double) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-contrast": String(amount)], styles: ["filter": "contrast(\(amount))"])
}

@inline(never)
func _saturationModifier(_ amount: Double) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-saturation": String(amount)], styles: ["filter": "saturate(\(amount))"])
}

@inline(never)
func _grayscaleModifier(_ amount: Double) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-grayscale": String(amount)], styles: ["filter": "grayscale(\(amount))"])
}

@inline(never)
func _colorInvertModifier() -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-color-invert": "true"], styles: ["filter": "invert(1)"])
}

@inline(never)
func _hueRotationModifier(_ angle: Angle) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-hue-rotation": String(angle.radians)], styles: ["filter": "hue-rotate(\(angle.radians)rad)"])
}

@inline(never)
func _listRowInsetsModifier(_ insets: EdgeInsets?) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-list-row-insets": insets.map { "\($0.top),\($0.leading),\($0.bottom),\($0.trailing)" } ?? "none"])
}

@inline(never)
func _fontWeightModifier(_ weight: Font.Weight?) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: weight.map { ["font-weight": $0.rawValue] } ?? .init())
}

@inline(never)
func _fontDesignModifier(_ design: Font.Design?) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: design.map { ["font-family": $0.rawValue] } ?? .init())
}

@inline(never)
func _textCaseModifier(_ textCase: Text.Case?) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: ["text-transform": textCase == .uppercase ? "uppercase" : textCase == .lowercase ? "lowercase" : "none"])
}

@inline(never)
func _textInputAutocapitalizationModifier(_ behavior: TextInputAutocapitalization?) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-text-input-autocapitalization": behavior?.rawValue ?? "sentences"])
}

@inline(never)
func _listStyleModifier(_ style: String) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-list-style": style])
}

@inline(never)
func _formStyleModifier(_ style: String) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-form-style": style])
}

@inline(never)
func _scrollBounceBehaviorModifier(_ behavior: ScrollBounceBehavior, axes: Axis.Set) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-scroll-bounce": behavior.rawValue])
}

@inline(never)
func _presentationDragIndicatorModifier(_ visibility: Visibility) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-presentation-drag-indicator": visibility.rawValue])
}

@inline(never)
func _toolbarBackgroundModifier(_ visibility: Visibility, for bars: [ToolbarPlacement]) -> _SemanticCompatibilityModifier {
  var attributes: _NodeValues = ["data-toolbar-background-visibility": visibility.rawValue]
  if !bars.isEmpty { attributes["data-toolbar-placement"] = bars.map { $0.rawValue }.joined(separator: ",") }
  return _SemanticCompatibilityModifier(attributes: attributes)
}

@inline(never)
func _minimumScaleFactorModifier(_ factor: Double) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-minimum-scale-factor": String(factor)])
}

@inline(never)
func _allowsHitTestingModifier(_ enabled: Bool) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-allows-hit-testing": enabled ? "true" : "false"], styles: enabled ? .init() : ["pointer-events": "none"])
}

@inline(never)
func _scrollIndicatorsModifier(_ visibility: ScrollIndicatorVisibility) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-scroll-indicators": visibility.rawValue], styles: visibility == .hidden || visibility == .never ? ["scrollbar-width": "none"] : .init())
}

@inline(never)
func _scrollDismissesKeyboardModifier(_ mode: ScrollDismissesKeyboardMode) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-scroll-dismisses-keyboard": mode.rawValue])
}

@inline(never)
func _scrollContentBackgroundModifier(_ visibility: Visibility) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(
      attributes: ["data-scroll-content-background": visibility.rawValue],
      styles: visibility == .hidden ? ["background": "transparent"] : .init(),
      environment: { $0._scrollContentBackgroundHidden = visibility == .hidden }
    )
}

@inline(never)
func _scrollEdgeEffectHiddenModifier(_ hidden: Bool, for edges: Edge.Set) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-scroll-edge-effect-hidden": hidden ? String(edges.rawValue) : "0"])
}

@inline(never)
func _scrollDisabledModifier(_ disabled: Bool) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-scroll-disabled": disabled ? "true" : "false"], styles: disabled ? ["overscroll-behavior": "none"] : .init())
}

@inline(never)
func _scrollClipDisabledModifier(_ disabled: Bool) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-scroll-clip-disabled": disabled ? "true" : "false"], styles: disabled ? ["overflow": "visible"] : .init())
}

@inline(never)
func _interactiveDismissDisabledModifier(_ disabled: Bool) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-interactive-dismiss-disabled": disabled ? "true" : "false"])
}

@inline(never)
func _presentationBackgroundInteractionModifier(_ interaction: PresentationBackgroundInteraction) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-presentation-background-interaction": interaction.rawValue])
}

@inline(never)
func _blendModeModifier(_ mode: BlendMode) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-blend-mode": mode.rawValue], styles: ["mix-blend-mode": _cssBlendMode(mode)])
}

@inline(never)
func _drawingGroupModifier(opaque: Bool, colorMode: ColorRenderingMode) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-drawing-group": "true", "data-drawing-opaque": opaque ? "true" : "false", "data-drawing-color-mode": colorMode.rawValue], styles: ["isolation": "isolate"])
}

/// The bars are carried as one space-separated attribute; no bars means every bar.
@inline(never)
func _toolbarColorSchemeModifier(_ scheme: ColorScheme?, for bars: [ToolbarPlacement]) -> _SemanticCompatibilityModifier {
  var attributes: _NodeValues = ["data-toolbar-color-scheme": scheme?.rawValue ?? "automatic"]
  if !bars.isEmpty {
    attributes["data-toolbar-placement"] = bars.map { $0.rawValue }.joined(separator: " ")
  }
  return _SemanticCompatibilityModifier(attributes: attributes)
}

@inline(never)
func _toolbarRoleModifier(_ role: ToolbarRole) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-toolbar-role": role.rawValue])
}

@inline(never)
func _textContentTypeModifier(_ type: UITextContentType?) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["autocomplete": type?.rawValue ?? "off"])
}

@inline(never)
func _submitLabelModifier(_ label: SubmitLabel) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-submit-label": label.rawValue])
}

@inline(never)
func _keyboardTypeModifier(_ type: UIKeyboardType) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-keyboard-type": type._webName])
}

@inline(never)
func _autocorrectionDisabledModifier(_ disabled: Bool) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["autocorrect": disabled ? "off" : "on"])
}

@inline(never)
func _dynamicTypeSizeModifier(_ size: DynamicTypeSize) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-dynamic-type-size": size.rawValue], environment: { $0.dynamicTypeSize = size })
}

@inline(never)
func _scrollTargetLayoutModifier(isEnabled: Bool) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-scroll-target-layout": isEnabled ? "true" : "false"])
}

@inline(never)
func _navigationBarBackButtonHiddenModifier(_ hidden: Bool) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-navigation-back-button-hidden": hidden ? "true" : "false"])
}

@inline(never)
func _listRowSeparatorModifier(_ visibility: Visibility, edges: Edge.Set) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-list-row-separator": visibility.rawValue])
}

@inline(never)
func _scaledToFit2Modifier() -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: ["object-fit": "contain"])
}

@inline(never)
func _scaledToFill2Modifier() -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: ["object-fit": "cover"])
}

@inline(never)
func _monospacedDigitModifier() -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(styles: ["font-variant-numeric": "tabular-nums"])
}

@inline(never)
func _labelsHiddenModifier() -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-labels-hidden": "true"], environment: { $0._labelsHidden = true })
}

/// `.ignoresSafeArea()` lets a view run into the safe areas around it (under a navigation bar: Tools/css-layout.js,
/// `extendUnderBars`); it does not change the size the view takes. A minimum of the whole container made Food Truck's
/// `Divider().ignoresSafeArea()` in the Donut Editor's HStack as wide as the stack, and pushed the form off the screen.
@inline(never)
func _ignoresSafeAreaModifier() -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-ignores-safe-area": "true"])
}

@inline(never)
func _compositingGroupModifier() -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-compositing-group": "true"], styles: ["isolation": "isolate"])
}

@inline(never)
func _zIndexModifier(_ value: Double) -> _SemanticCompatibilityModifier {
  let bounded = value.isFinite ? min(max(value, -2_000_000_000), 2_000_000_000) : 0
  let integer = Int(bounded >= 0 ? bounded.rounded(.up) : bounded.rounded(.down))
  return _SemanticCompatibilityModifier(styles: ["z-index": String(integer)])
}

@inline(never)
func _contentTransitionModifier(_ transition: ContentTransition) -> _SemanticCompatibilityModifier {
  var attributes: _NodeValues = ["data-content-transition": transition.token]
  if let direction = transition.direction { attributes["data-content-transition-direction"] = direction }
  if let value = transition.value, value.isFinite { attributes["data-content-transition-value"] = String(value) }
  if let options = transition.options {
    if options.speedValue != 1 { attributes["data-content-transition-speed"] = String(options.speedValue) }
    if let count = options.repeatCount { attributes["data-content-transition-repeat"] = String(count) }
  }
  return _SemanticCompatibilityModifier(attributes: attributes)
}

@inline(never)
func _swipeActionsModifier(edge: String, allowsFullSwipe: Bool, content: @escaping () -> AnyView) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(
    attributes: [
      "data-swipe-actions": "true",
      "data-swipe-edge": edge,
      "data-swipe-full-swipe": allowsFullSwipe ? "true" : "false"
    ],
    swipeContent: content
  )
}

@inline(never)
func _toolbarBackgroundStyleModifier(_ cssValue: String) -> _SemanticCompatibilityModifier {
  _SemanticCompatibilityModifier(attributes: ["data-toolbar-background": cssValue])
}

@inline(never)
func _toolbarBackgroundStyleModifier(_ cssValue: String, for bars: [ToolbarPlacement]) -> _SemanticCompatibilityModifier {
  var attributes: _NodeValues = ["data-toolbar-background": cssValue]
  if !bars.isEmpty { attributes["data-toolbar-placement"] = bars.map { $0.rawValue }.joined(separator: ",") }
  return _SemanticCompatibilityModifier(attributes: attributes)
}

@inline(never)
func _scrollTargetBehaviorModifier(_ behavior: String) -> _SemanticCompatibilityModifier {
  let token = behavior
  return _SemanticCompatibilityModifier(attributes: ["data-scroll-target-behavior": token])
}
