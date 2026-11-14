/// The renderer-neutral accessibility backend.
///
/// SwiftUI modifiers describe intent here and the backend resolves that intent
/// against the element that will carry it.  Native HTML semantics win: ARIA is
/// emitted only for states or roles that HTML cannot express on that element.
/// Keeping this decision in one place prevents a modifier boundary from
/// accidentally replacing a button with a second, conflicting role.
package struct _AccessibilitySemantics {
  var label: String?
  var value: String?
  var hint: String?
  var addTraits: AccessibilityTraits
  var removeTraits: AccessibilityTraits
  var hidden: Bool?

  package init(
    label: String? = nil,
    value: String? = nil,
    hint: String? = nil,
    addTraits: AccessibilityTraits = [],
    removeTraits: AccessibilityTraits = [],
    hidden: Bool? = nil
  ) {
    self.label = label
    self.value = value
    self.hint = hint
    self.addTraits = addTraits
    self.removeTraits = removeTraits
    self.hidden = hidden
  }
}

package enum _AccessibilityBackend {
  package static func setLabel(_ value: String, on node: _RenderNode) {
    node.attributes["aria-label"] = value
    node.attributes["data-a11y-backend"] = "1"
  }

  static func setState(_ name: String, _ value: String, on node: _RenderNode) {
    node.attributes["aria-\(name)"] = value
    node.attributes["data-a11y-backend"] = "1"
  }

  static func setNumeric(_ value: String, name: String, on node: _RenderNode) {
    setState(name, value, on: node)
  }

  static func synchronizeHiddenHitTesting(on node: _RenderNode) {
    let hiddenAndNonInteractive = node.attributes["aria-hidden"] == "true"
      && node.attributes["data-allows-hit-testing"] == "false"
    if hiddenAndNonInteractive {
      if node.attributes["inert"] == nil {
        node.attributes["inert"] = ""
        node.attributes["data-a11y-inert"] = "hit-testing"
      }
    } else if node.attributes["data-a11y-inert"] == "hit-testing" {
      node.attributes.removeValue(forKey: "inert")
      node.attributes.removeValue(forKey: "data-a11y-inert")
    }
  }

  package static func apply(_ semantics: _AccessibilitySemantics, to node: _RenderNode) {
    if let label = semantics.label { setLabel(label, on: node) }
    if semantics.value != nil || semantics.hint != nil {
      applyValueAndHint(semantics, to: metadataTarget(node))
    }

    if let hidden = semantics.hidden {
      if hidden { node.attributes["aria-hidden"] = "true" }
      else { node.attributes.removeValue(forKey: "aria-hidden") }
    }
    synchronizeHiddenHitTesting(on: node)

    let previousTraits = node.attributes["data-a11y-traits"]
      .flatMap(UInt64.init)
      .map(AccessibilityTraits.init(rawValue:)) ?? []
    let updatesTraits = !semantics.addTraits.isEmpty || !semantics.removeTraits.isEmpty
    let traits = previousTraits.union(semantics.addTraits).subtracting(semantics.removeTraits)
    if updatesTraits || node.attributes["data-a11y-traits"] != nil {
      if let previousRole = role(for: previousTraits), node.attributes["role"] == previousRole {
        node.attributes.removeValue(forKey: "role")
      }
      node.attributes["data-a11y-traits"] = String(traits.rawValue)
    }
    if let role = role(for: traits) { setRole(role, on: node) }

    if traits.contains(.isSelected) { node.attributes["aria-selected"] = "true" }
    if traits.contains(.isDisabled), !hasNativeDisabledState(node) {
      node.attributes["aria-disabled"] = "true"
    }
    if traits.contains(.updatesFrequently), node.attributes["aria-live"] == nil {
      node.attributes["aria-live"] = "polite"
    }

    // This marker is intentionally stable and has no visual meaning.  It lets
    // browser audits distinguish resolved accessibility metadata from an
    // application-supplied, potentially conflicting ARIA attribute.
    node.attributes["data-a11y-backend"] = "1"
  }

  // Layout wrappers do not create a new accessible element. Follow their
  // content slot so metadata stays on the actual control, not an anonymous div.
  private static func metadataTarget(_ node: _RenderNode) -> _RenderNode {
    let kind = node.attributes["data-layout-kind"] ?? ""
    let transparent = ["frame", "padding", "fixed", "offset", "position", "background", "overlay", "container-relative"]
    guard transparent.contains(kind), !node.children.isEmpty else { return node }
    let content = kind == "background" ? node.children.last! : node.children[0]
    return metadataTarget(content)
  }

  private static func applyValueAndHint(_ semantics: _AccessibilitySemantics, to node: _RenderNode) {
    if let value = semantics.value { node.attributes["data-a11y-value"] = value }
    if let hint = semantics.hint { node.attributes["data-a11y-hint"] = hint }
    let value = node.attributes["data-a11y-value"] ?? ""
    let hint = node.attributes["data-a11y-hint"] ?? ""
    let role = node.attributes["role"] ?? ""
    let inputType = node.attributes["type"] ?? ""
    let tag: String
    if case .element(let name) = node.kind { tag = name } else { tag = "" }
    let isRange = ["slider", "spinbutton", "progressbar", "meter", "scrollbar", "separator"].contains(role)
      || ["progress", "meter"].contains(tag)
      || (tag == "input" && ["range", "number"].contains(inputType))
    if isRange && !value.isEmpty { node.attributes["aria-valuetext"] = value }
    else { node.attributes.removeValue(forKey: "aria-valuetext") }
    let description = (isRange ? [hint] : [value, hint]).filter { !$0.isEmpty }.joined(separator: ". ")
    if description.isEmpty { node.attributes.removeValue(forKey: "aria-description") }
    else { node.attributes["aria-description"] = description }
    node.attributes["data-a11y-backend"] = "1"
  }

  private static func setRole(_ role: String, on node: _RenderNode) {
    guard !hasNativeRole(role, for: node) else { return }
    node.attributes["role"] = role
  }

  private static func role(for traits: AccessibilityTraits) -> String? {
    if traits.contains(.isButton) { return "button" }
    if traits.contains(.isLink) { return "link" }
    if traits.contains(.isHeader) { return "heading" }
    if traits.contains(.isImage) { return "img" }
    return nil
  }

  private static func hasNativeRole(_ role: String, for node: _RenderNode) -> Bool {
    guard case .element(let tag) = node.kind else { return false }
    switch (tag.lowercased(), role) {
    case ("button", "button"), ("a", "link"), ("img", "img"),
         ("progress", "progressbar"), ("meter", "meter"),
         ("h1", "heading"), ("h2", "heading"), ("h3", "heading"),
         ("h4", "heading"), ("h5", "heading"), ("h6", "heading"),
         ("nav", "navigation"), ("main", "main"), ("aside", "complementary"),
         ("table", "table"), ("th", "columnheader"), ("td", "cell"):
      return true
    default:
      return false
    }
  }

  private static func hasNativeDisabledState(_ node: _RenderNode) -> Bool {
    node.attributes["disabled"] != nil || node.attributes["inert"] != nil
  }
}
