@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
// Effects around SwiftUI's motion: symbol transitions, visual effects read from geometry, color multiplication, scroll
// indicator flashes, and scroll transitions that differ on each edge.

// MARK: Symbol transitions

/// A symbol effect that can show or hide a symbol: `Transition.symbolEffect(_:options:)`.
public protocol TransitionSymbolEffect {}
/// A symbol effect that can replace one symbol by another: `ContentTransition.symbolEffect(_:options:)`.
public protocol ContentTransitionSymbolEffect {}

extension AppearSymbolEffect: TransitionSymbolEffect {}
extension DisappearSymbolEffect: TransitionSymbolEffect {}
extension AutomaticSymbolEffect: TransitionSymbolEffect, ContentTransitionSymbolEffect {}
extension ReplaceSymbolEffect: ContentTransitionSymbolEffect {}
extension ReplaceSymbolEffect.MagicReplace: ContentTransitionSymbolEffect {}

public extension ContentTransition {
  /// A symbol replaced by another plays `effect` (a replace) as it changes.
  static func symbolEffect<T>(_ effect: T, options: SymbolEffectOptions = .default) -> ContentTransition where T: ContentTransitionSymbolEffect, T: SymbolEffect {
    let name = effect._swiftUIWebSymbolEffectName
    // The automatic effect of a replaced symbol is a replace.
    return ContentTransition(token: "symbol-effect", direction: name == "bounce" ? "replace-down-up" : name, options: options)
  }

  /// A symbol replaced by another plays the automatic replace.
  static var symbolEffect: ContentTransition { symbolEffect(.automatic) }
}

/// A transition that shows and hides a symbol with a symbol effect: it appears scaled up from half its size, and
/// disappears the same way back.
@MainActor @frozen @preconcurrency public struct SymbolEffectTransition: Transition {
  let effect: String
  let options: SymbolEffectOptions
  @MainActor @preconcurrency public init<T>(effect: T, options: SymbolEffectOptions) where T: SymbolEffect, T: TransitionSymbolEffect {
    self.effect = effect._swiftUIWebSymbolEffectName
    self.options = options
  }
  @MainActor @preconcurrency public func body(content: SymbolEffectTransition.Content, phase: TransitionPhase) -> some View { content }
  @MainActor @preconcurrency public static let properties = TransitionProperties()
  nonisolated public var _swiftUIWebAnyTransition: AnyTransition? {
    // `appear-down` and `disappear-down` grow from (or to) one and a half times the size; the others from half.
    let scale = effect.hasSuffix("-down") ? 1.5 : 0.5
    let state = _TransitionState.opacity(0).combined(with: .scale(scale, anchor: .center))
    return AnyTransition("symbol-effect(\(effect))", insertion: state, removal: state, playback: options)
  }
}

public extension Transition where Self == SymbolEffectTransition {
  @MainActor @preconcurrency static func symbolEffect<T>(_ effect: T, options: SymbolEffectOptions = .default) -> SymbolEffectTransition where T: SymbolEffect, T: TransitionSymbolEffect {
    SymbolEffectTransition(effect: effect, options: options)
  }
  @MainActor @preconcurrency static var symbolEffect: SymbolEffectTransition { SymbolEffectTransition(effect: AppearSymbolEffect(), options: .default) }
}

private struct _SymbolEffectsRemovedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
  /// Whether `symbolEffectsRemoved()` above turned the symbol effects off.
  var _symbolEffectsRemoved: Bool {
    get { self[_SymbolEffectsRemovedKey.self] }
    set { self[_SymbolEffectsRemovedKey.self] = newValue }
  }
}

public extension View {
  /// Turns off the symbol effects below this view (`symbolEffect`), when `isEnabled`.
  nonisolated func symbolEffectsRemoved(_ isEnabled: Bool = true) -> some View {
    environment(\._symbolEffectsRemoved, isEnabled)
  }
}

/// The attributes of a symbol effect, left out where `symbolEffectsRemoved()` turned symbol effects off.
nonisolated struct _SymbolEffectModifier: ViewModifier {
  let attributes: _NodeValues
  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard !context.environment._symbolEffectsRemoved else { return }
    for (key, value) in attributes { node.attributes[key] = value }
  }
}

// MARK: Visual effects

public extension VisualEffect {
  func offset(_ offset: CGSize) -> some VisualEffect { self.offset(x: offset.width, y: offset.height) }
  func brightness(_ amount: Double) -> some VisualEffect { _appendingFilter("brightness(\(_transitionNumber(1 + amount)))") }
  func contrast(_ amount: Double) -> some VisualEffect { _appendingFilter("contrast(\(_transitionNumber(amount)))") }
  func grayscale(_ amount: Double) -> some VisualEffect { _appendingFilter("grayscale(\(_transitionNumber(min(max(amount, 0), 1))))") }
  func saturation(_ amount: Double) -> some VisualEffect { _appendingFilter("saturate(\(_transitionNumber(max(amount, 0))))") }
  func hueRotation(_ angle: Angle) -> some VisualEffect { _appendingFilter("hue-rotate(\(_transitionNumber(angle.radians * 180 / Double.pi))deg)") }
  func blendMode(_ blendMode: BlendMode) -> some VisualEffect { _setting("mix-blend-mode", _cssBlendMode(blendMode)) }
  func transformEffect(_ transform: CGAffineTransform) -> some VisualEffect { transformEffect(ProjectionTransform(transform)) }
  func transformEffect(_ transform: ProjectionTransform) -> some VisualEffect { _appendingTransform(transform._cssMatrix) }
  func rotation3DEffect(_ angle: Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat), anchor: UnitPoint = .center, anchorZ: CGFloat = 0, perspective: CGFloat = 1) -> some VisualEffect {
    _appendingTransform("perspective(\(_transitionNumber(max(1, 1000 / max(perspective, 0.001))))px) rotate3d(\(_transitionNumber(axis.x)),\(_transitionNumber(axis.y)),\(_transitionNumber(axis.z)),\(_transitionNumber(angle.radians * 180 / Double.pi))deg)")
  }
  /// Shaders are Metal functions, which a browser cannot run: the effect draws the view unchanged.
  func colorEffect(_ shader: Shader, isEnabled: Bool = true) -> some VisualEffect { self }
  /// Shaders are Metal functions, which a browser cannot run: the effect draws the view unchanged.
  func distortionEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some VisualEffect { self }
  /// Shaders are Metal functions, which a browser cannot run: the effect draws the view unchanged.
  func layerEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some VisualEffect { self }

  fileprivate func _setting(_ key: String, _ value: String) -> Self {
    var copy = _swiftUIWebProperties
    copy[key] = value
    return Self(_swiftUIWebProperties: copy)
  }

  fileprivate func _appendingTransform(_ transform: String) -> Self {
    _setting("transform", [_swiftUIWebProperties["transform"], transform].compactMap { $0 }.joined(separator: " "))
  }

  fileprivate func _appendingFilter(_ filter: String) -> Self {
    _setting("filter", [_swiftUIWebProperties["filter"], filter].compactMap { $0 }.joined(separator: " "))
  }
}


public extension View {
  /// Applies the effect `effect` returns for the view's geometry, again whenever that geometry changes (a frame in a
  /// scroll view, read as it scrolls).
  nonisolated func visualEffect(_ effect: @escaping @Sendable (EmptyVisualEffect, GeometryProxy) -> some VisualEffect) -> some View {
    _VisualEffectView(content: self, encode: { proxy in effect(EmptyVisualEffect(), proxy)._swiftUIWebEncoded })
  }
}

/// The view `visualEffect` returns: its content with the effect of the geometry last measured. The effect is made again in
/// every render from that geometry, not only when the geometry changes: its closure may read state (`isOn ? 1 : 0.3`), and a
/// change of that state must show.
nonisolated struct _VisualEffectView<Content: View>: View {
  let content: Content
  let encode: @Sendable (GeometryProxy) -> String
  @State(memberID: 3141592653) private var measured: _MeasuredGeometry? = nil

  var body: some View {
    let encode = self.encode
    return content
      .modifier(_EncodedVisualEffect(encoded: measured.map { encode($0.proxy) } ?? ""))
      .modifier(_UntransformedGeometryModifier())
      // The effect is run on the proxy so that what it reads of it (a position, which the page then follows as an ancestor
      // scrolls) is noted; the measurement is what is kept.
      .onGeometryChange(for: _MeasuredGeometry.self, of: { proxy in _ = encode(proxy); return proxy._measured }) { measured = $0 }
  }
}

/// Marks the node a `visualEffect` measures: the host measures it without its own transform (geometry-host.js), since the
/// effect's transform is on that same node and would otherwise move what the effect reads, and the effect would chase itself.
nonisolated struct _UntransformedGeometryModifier: ViewModifier {
  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-geometry-untransformed"] = "true"
  }
}

/// Writes an encoded visual effect (`opacity=0.5;transform=…`) on the node, after what the node has.
nonisolated struct _EncodedVisualEffect: ViewModifier {
  let encoded: String
  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    for entry in encoded.split(separator: ";") {
      guard let equals = entry.firstIndex(of: "=") else { continue }
      let key = String(entry[..<equals]), value = String(entry[entry.index(after: equals)...])
      switch key {
      case "transform", "filter":
        if let existing = node.styles[key], !existing.isEmpty, existing != "none" { node.styles[key] = existing + " " + value } else { node.styles[key] = value }
      case "opacity":
        // The effect dims what the view already has: its opacity multiplies the view's.
        if let existing = node.styles[key], let base = Double(existing), let next = Double(value) { node.styles[key] = String(base * next) } else { node.styles[key] = value }
      default:
        node.styles[key] = value
      }
    }
  }
}

// MARK: Color multiplication

public extension View {
  /// Multiplies each color channel of the view by `color`'s: white leaves it unchanged, black makes it black.
  nonisolated func colorMultiply(_ color: Color) -> some View {
    modifier(_ColorMultiplyModifier(color: color))
  }
}

/// `colorMultiply`: an SVG color matrix that scales the channels, which the page defines once per color
/// (`data-color-multiply`, embedded-dom.js) and the view's filter references.
nonisolated struct _ColorMultiplyModifier: ViewModifier {
  let color: Color
  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let resolved = color.resolve(in: context.environment)
    let channels = [Double(resolved.red), Double(resolved.green), Double(resolved.blue), Double(resolved.opacity)]
    let matrix = channels.map { _transitionNumber($0) }.joined(separator: " ")
    // Each multiplier keeps its own matrix and its own reference in the filter, in order: a filter between two of them
    // (`contrast`) need not commute with either, so they are not combined. The page defines every matrix the attribute lists.
    if let earlier = node.attributes["data-color-multiply"] { node.attributes["data-color-multiply"] = earlier + ";" + matrix } else { node.attributes["data-color-multiply"] = matrix }
    let reference = "url(#\(_colorMultiplyID(channels)))"
    if let existing = node.styles["filter"], !existing.isEmpty, existing != "none" { node.styles["filter"] = existing + " " + reference } else { node.styles["filter"] = reference }
  }
}

/// The id of the page's filter for a channel multiplier (`embedded-dom.js` defines it from `data-color-multiply`).
func _colorMultiplyID(_ channels: [Double]) -> String {
  "swu-multiply-" + channels.map { String(_transitionNumber($0).map { $0 == "." ? "_" : $0 == "-" ? "m" : $0 }) }.joined(separator: "-")
}

// MARK: Scroll indicators

public extension View {
  /// Flashes the scroll indicators of the scroll views below whenever `value` changes.
  nonisolated func scrollIndicatorsFlash(trigger value: some Equatable) -> some View {
    nonisolated(unsafe) let value = value
    return modifier(_ScrollFlashModifier(generation: { store, key in store._identityGeneration(key: key, value: value) }, onAppear: false))
  }

  /// Flashes the scroll indicators of the scroll views below when they appear, if `onAppear`.
  nonisolated func scrollIndicatorsFlash(onAppear: Bool) -> some View {
    modifier(_ScrollFlashModifier(generation: nil, onAppear: onAppear))
  }
}

/// The host flashes the indicators of the scroll views under a node whose `data-scroll-flash` changes, or that appears
/// with `data-scroll-flash-on-appear` (embedded-dom.js). The trigger is published as a generation that advances when the
/// value stops being equal to the one rendered here before, as a task's identity is: any `Equatable` value triggers, whether
/// or not it has a description (in Embedded Swift a struct or an enum without a raw value has none).
nonisolated struct _ScrollFlashModifier: ViewModifier {
  let generation: (@MainActor (StateStore, String) -> UInt64)?
  let onAppear: Bool
  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // A speculative render (the hovered look of a hover effect) must not advance the history of the real one.
    if let generation, !context._speculative {
      node.attributes["data-scroll-flash"] = String(generation(context.stateStore, context._modifierStateKey("#scroll-flash")))
    }
    if onAppear { node.attributes["data-scroll-flash-on-appear"] = "true" }
  }
}

// MARK: Scroll transitions on each edge

public extension View {
  /// A scroll transition whose configuration differs on the leading and trailing edges of the scroll view.
  nonisolated func scrollTransition(
    topLeading: ScrollTransitionConfiguration,
    bottomTrailing: ScrollTransitionConfiguration,
    axis: Axis? = nil,
    transition: @escaping @Sendable (EmptyVisualEffect, ScrollTransitionPhase) -> some VisualEffect
  ) -> some View {
    scrollTransition(topLeading, axis: axis, transition: transition)
      .modifier(_ScrollTransitionTrailingModifier(configuration: bottomTrailing))
  }
}

/// The configuration of the trailing edge, beside the leading one the scroll transition publishes: the host measures an
/// element past the trailing edge against its threshold and inset (transition-host.js).
nonisolated struct _ScrollTransitionTrailingModifier: ViewModifier {
  let configuration: ScrollTransitionConfiguration
  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    for (key, value) in configuration.attributes {
      let prefix = "data-scroll-transition-"
      guard key.hasPrefix(prefix) else { continue }
      node.attributes[prefix + "trailing-" + String(key.dropFirst(prefix.count))] = value
    }
  }
}
