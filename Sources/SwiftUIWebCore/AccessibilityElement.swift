

package let _interactiveTags: Set<String> = ["button", "a", "input", "select", "textarea", "details", "summary", "iframe", "video", "audio"]

/// Descendant labels in document order, following the accessible-name rules
/// that matter for SwiftUI content: hidden subtrees are skipped, an explicit
/// label replaces its subtree's text, and each text leaf is one label.
package func _accessibleLabels(_ node: _RenderNode) -> [String] {
  if node.attributes["aria-hidden"] == "true" { return [] }
  if let label = node.attributes["aria-label"], !label.isEmpty { return [label] }
  if node.kind == .text {
    guard let text = node.text else { return [] }
    let trimmed = String(text.drop(while: { $0 == " " || $0 == "\n" }).reversed().drop(while: { $0 == " " || $0 == "\n" }).reversed())
    return trimmed.isEmpty ? [] : [trimmed]
  }
  if case .element("img") = node.kind, let alt = node.attributes["alt"], !alt.isEmpty { return [alt] }
  return node.children.flatMap(_accessibleLabels)
}

