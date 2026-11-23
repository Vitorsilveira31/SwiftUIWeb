@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

/// How an accessibility element created by `accessibilityElement(children:)`
/// treats its descendants (SwiftUI's `AccessibilityChildBehavior`).
public struct AccessibilityChildBehavior: Hashable, Sendable {
  let rawValue: String
  /// The element is a leaf: descendants are hidden from assistive technology
  /// and the element carries only its own label/value/traits.
  public static let ignore = AccessibilityChildBehavior(rawValue: "ignore")
  /// Descendants stay separate elements inside a grouping container.
  public static let contain = AccessibilityChildBehavior(rawValue: "contain")
  /// Descendants are merged into one element whose label joins theirs.
  public static let combine = AccessibilityChildBehavior(rawValue: "combine")
}

public extension View {
  /// Creates a new accessibility element (or container) for this view.
  ///
  /// ARIA realization: `.contain` is a `role="group"` container whose
  /// children remain individually reachable (a contained `ScrollView` is a
  /// `role="region"` landmark instead, so a labeled, `focusable()` surface
  /// such as a wide table can be found and scrolled sideways from the
  /// keyboard); `.combine` is one element named
  /// by the descendants' labels joined with ", "; `.ignore` is one element
  /// with only the label/traits applied to it. For `.combine` and `.ignore`
  /// non-interactive descendants are `aria-hidden`. Focusable descendants
  /// (buttons, fields, links) stay reachable, because hiding a focusable
  /// control from assistive technology is invalid on the web.
  nonisolated func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View {
    _modified(AccessibilityElementModifier(behavior: children))
  }
}

package nonisolated struct AccessibilityElementModifier: ViewModifier {
  package let behavior: AccessibilityChildBehavior
  package init(behavior: AccessibilityChildBehavior) { self.behavior = behavior }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if node.kind == .fragment {
      // A Group has no DOM host. Give the new element one that does not
      // participate in CSS layout, so geometry is unchanged.
      node.kind = .element("div")
      node.styles["display"] = "contents"
    } else if node.kind == .text {
      // A single Text is already one element; wrap it so ARIA attributes
      // can be attached without changing its rendered text.
      let text = node.cloneSharingChildren()
      text.key = nil
      node.kind = .element("span")
      node.text = nil
      node.children = [text]
    }
    node.attributes["data-a11y-children"] = behavior.rawValue
    node.attributes["data-a11y-backend"] = "1"
    if node.attributes["role"] == nil, !_hasNativeElementSemantics(node) {
      // A contained scrolling surface is a named landmark, not a mere
      // grouping: readers list it and keyboards reach it (with `focusable()`)
      // so wide tables can be scrolled sideways without a pointer.
      let isScrollSurface = node.attributes["data-scroll-node"] == "true"
      node.attributes["role"] = behavior == .contain && isScrollSurface ? "region" : "group"
    }
    guard behavior != .contain else { return }
    if behavior == .combine, node.attributes["aria-label"] == nil {
      let label = node.children.flatMap(_accessibleLabels).joined(separator: ", ")
      if !label.isEmpty { node.attributes["aria-label"] = label }
    }
    for child in node.children { _hideNonInteractive(child) }
  }
}

private func _hasNativeElementSemantics(_ node: _RenderNode) -> Bool {
  guard case .element(let tag) = node.kind else { return false }
  return _interactiveTags.contains(tag) || ["img", "h1", "h2", "h3", "h4", "h5", "h6", "progress", "meter", "table", "ul", "ol", "li", "nav", "main"].contains(tag)
}

private func _isInteractive(_ node: _RenderNode) -> Bool {
  if case .element(let tag) = node.kind, _interactiveTags.contains(tag) { return true }
  if let index = node.attributes["tabindex"], index != "-1" { return true }
  if let role = node.attributes["role"], ["button", "link", "checkbox", "switch", "slider", "textbox", "tab", "menuitem"].contains(role) { return true }
  return !node.events.isEmpty && node.events.keys.contains("click")
}

private func _containsInteractive(_ node: _RenderNode) -> Bool {
  _isInteractive(node) || node.children.contains(where: _containsInteractive)
}

private func _hideNonInteractive(_ node: _RenderNode) {
  if node.kind == .empty { return }
  if node.kind == .fragment || _containsInteractive(node) {
    if _isInteractive(node) { return }
    for child in node.children { _hideNonInteractive(child) }
    return
  }
  node.attributes["aria-hidden"] = "true"
}
