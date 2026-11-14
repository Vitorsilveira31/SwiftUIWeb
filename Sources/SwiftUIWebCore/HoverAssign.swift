/// State that a `.onHover { hovered = $0 }` assignment toggles. The renderer
/// uses it to render the view once with the value flipped and turn the visual
/// difference into a CSS `:hover` rule, so the pointer moving over the view
/// costs no Swift work.
@_spi(Renderer) public final class _HoverProbe {
  /// Sets the hovered state without notifying anyone; returns the old value.
  public let setSilently: (Bool) -> Bool
  /// The render owner of the view that declares the state.
  public let ownerToken: UInt64?

  init(setSilently: @escaping (Bool) -> Bool, ownerToken: UInt64?) {
    self.setSilently = setSilently
    self.ownerToken = ownerToken
  }
}

/// `onHover` for the common case where the action only assigns the pointer
/// state to a `@State` value. The web build lowers those assignments to this
/// modifier; enter/leave events stay registered as the fallback for views whose
/// hovered look cannot be expressed as styles alone.
nonisolated struct HoverAssignModifier: ViewModifier {
  private let state: State<Bool>
  init(state: State<Bool>) { self.state = state }

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let state = self.state
    node.events["mouseenter"] = _EventHandler(name: "mouseenter", action: { state.wrappedValue = true })
    node.events["mouseleave"] = _EventHandler(name: "mouseleave", action: { state.wrappedValue = false })
    let ownerToken = StateRuntime.scope?.ownerToken
    // Enclosing owners often return this same node; the probe must still find
    // the Fiber that holds it.
    if let ownerToken { context._renderOwnerRegistry?._markAliasable(ownerToken) }
    node._hoverProbe = _HoverProbe(setSilently: state._silentSetter(), ownerToken: ownerToken)
  }
}

public extension View {
  nonisolated func onHover(_assigning state: State<Bool>) -> some View {
    ModifiedContent(content: self, modifier: HoverAssignModifier(state: state))
  }
}

/// The visual difference between a view's normal and hovered render, as CSS
/// declarations per node. `nil` from `_hoverDifferences` means the hovered
/// render changes more than styles (text, structure, attributes), so the
/// pointer events must stay with Swift.
private let _hoverMirrorAttributes: Set<String> = [
  "data-background-style", "data-foreground-style", "data-color-style", "data-color", "data-shape-style", "data-shape-paint", "data-content-shape"
]
/// Classes the renderer adds to a node after the view rendered it (a lazy
/// grid's cell wrapper); a speculative render never sees them.
private func _hoverComparableClasses(_ classes: [String]) -> [String] {
  classes.filter { $0 != "lazy-cell" }
}
private let _hoverPaintAttributes: Set<String> = [
  "fill", "stroke", "stroke-width", "fill-opacity", "stroke-opacity", "opacity"
]

/// `normalChildren` lets the caller say where the retained tree's real children
/// live: a retained node's own `children` can lag behind the Fibers that were
/// re-rendered independently since.
@_spi(Renderer) public func _hoverDifferences(
  normal: _RenderNode,
  hovered: _RenderNode,
  normalChildren: (_RenderNode) -> [_RenderNode] = { $0.children }
) -> [(normalNode: _RenderNode, declarations: _NodeValues)]? {
  var result: [(normalNode: _RenderNode, declarations: _NodeValues)] = []
  func walk(_ a: _RenderNode, _ b: _RenderNode) -> Bool {
    if a.kind != b.kind || a.text != b.text { return false }
    let aChildren = normalChildren(a)
    if aChildren.count != b.children.count { return false }
    if a.lazyCollection != nil || b.lazyCollection != nil { return false }
    if _hoverComparableClasses(a.classes) != _hoverComparableClasses(b.classes) { return false }
    var declarations: _NodeValues = [:]
    // SVG paint attributes have a CSS property of the same name, so a change in
    // one of them is a style change; metadata that only mirrors a style is
    // ignored; any other attribute change is not expressible in CSS.
    for name in Set(a.attributes.keys).union(b.attributes.keys) {
      let before = a.attributes[name], after = b.attributes[name]
      // The value generation of an `.animation(_:value:)` is history, which a speculative render does not write.
      if before == after || _hoverMirrorAttributes.contains(name) || name.hasPrefix("data-lazy-") || name == "data-animation-value" { continue }
      guard let after, before != nil, _hoverPaintAttributes.contains(name) else { return false }
      declarations[name] = after
    }
    if a.styles != b.styles {
      for (name, value) in b.styles where a.styles[name] != value { declarations[name] = value }
      // A property the hovered render omits returns to its default, which
      // CSS spells `unset` (inherit for inherited properties, else initial).
      for name in a.styles.keys where b.styles[name] == nil { declarations[name] = "unset" }
    }
    if !declarations.isEmpty { result.append((a, declarations)) }
    for index in aChildren.indices where !walk(aChildren[index], b.children[index]) { return false }
    return true
  }
  return walk(normal, hovered) ? result : nil
}

/// CSS text for one hover trigger. While the trigger is hovered, every node
/// that differs switches to its hovered declarations. The condition is scoped to
/// the view that owns the state: `owner:has(trigger:hover)`, or `owner:hover`
/// when the trigger is the owner's own root. A target without a transition of its
/// own eases into and out of the hovered look: with the timing of the
/// `.animation(_:value:)` on it (`animation`), else with a short default.
@_spi(Renderer) public func _hoverRuleCSS(
  ownerSelector: String,
  triggerSelector: String,
  targets: [(selector: String, isOwnerRoot: Bool, declarations: _NodeValues, hasTransition: Bool, animation: String?)]
) -> String {
  let context = ownerSelector == triggerSelector ? "\(ownerSelector):hover" : "\(ownerSelector):has(\(triggerSelector):hover)"
  var css = ""
  for target in targets {
    let names = target.declarations.keys.sorted().filter(_isHoverCSSName)
    let body = names.map { "\($0):\(_hoverCSSValue(target.declarations[$0] ?? "")) !important" }.joined(separator: ";")
    if let animation = target.animation, !target.hasTransition {
      let timing = _hoverCSSValue(animation)
      css += "\(target.selector){transition:\(names.map { "\($0) \(timing)" }.joined(separator: ","))}"
    } else if !target.hasTransition {
      css += "\(target.selector){transition-property:\(names.joined(separator: ","));transition-duration:.15s;transition-timing-function:ease}"
    }
    css += "\(target.isOwnerRoot ? context : context + " " + target.selector){\(body)}"
  }
  return css
}

/// A style name in a hover rule: letters, digits, `-` and `_` only.
private func _isHoverCSSName(_ name: String) -> Bool {
  !name.isEmpty && name.utf8.allSatisfy { byte in
    (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
      || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_")
  }
}

/// A style value in a hover rule, without the characters that could close the
/// declaration, the rule, or the `<style>` element it is written into.
private func _hoverCSSValue(_ value: String) -> String {
  var result = ""
  for scalar in value.unicodeScalars {
    switch scalar {
    // A line break would also end the rule's line in the hover-rule list the page reads.
    case "{", "}", ";", "<", ">", "\n", "\r": continue
    default: result.unicodeScalars.append(scalar)
    }
  }
  return result
}
