@_spi(Renderer) import SwiftUIWebTransferable

/// One declaration recorded by a Text-returning modifier: a CSS property or,
/// for renderer metadata shared with the View modifiers, an attribute.
package struct _TextStyleDeclaration {
  let property: String
  let value: String
  var isAttribute = false

  package init(property: String, value: String, isAttribute: Bool = false) {
    self.property = property
    self.value = value
    self.isAttribute = isAttribute
  }
}

/// SwiftUI's Text-returning modifiers and `Text + Text` concatenation.
///
/// Apple's `Text` exposes these modifiers as members that return `Text`, which
/// is what makes rich runs such as
/// `Text("8 tasks").bold() + Text(" and ") + Text("1 job").foregroundColor(.red)`
/// compile. The members below mirror the parameter types of the corresponding
/// `View` modifiers so that overload resolution always prefers the concrete
/// `Text` member (a more specialized declaration context) and existing call
/// sites keep compiling. The result still conforms to `View`, so chained view
/// modifiers such as `.lineLimit(2)` or `.padding()` are unchanged.
///
/// Rendering: an ordinary Text stays one text node carrying its declarations.
/// A concatenation renders one `span` text leaf whose runs are inline child
/// spans. Modifiers applied to the concatenation style the outer span and are
/// inherited by the runs; a run's own modifiers take precedence, matching
/// SwiftUI's "inner modifier wins" behavior.
extension Text {

  public nonisolated func font(_ font: Font) -> Text {
    var copy = self
    for key in _sortedFontKeys(font) {
      if let value = font.cssStyles[key] { copy._textStyles.append(_TextStyleDeclaration(property: key, value: value)) }
    }
    return copy
  }
  public func font(_ font: Font?) -> Text {
    guard let font else { return self }
    return self.font(font)
  }
  public nonisolated func underline(_ active: Bool = true, color: Color? = nil) -> Text {
    var copy = _styled("text-decoration-line", active ? "underline" : "none")
    if let color { copy = copy._styled("text-decoration-color", color.cssValue) }
    return copy
  }
  public nonisolated func tracking(_ value: Double) -> Text { _styled("letter-spacing", "\(_textPixels(value))px") }
  @_disfavoredOverload public func tracking(_ value: Float) -> Text { tracking(Double(value)) }

  func _applyTextStyles(to node: _RenderNode) {
    for declaration in _textStyles {
      if declaration.isAttribute { node.attributes[declaration.property] = declaration.value }
      else { node.styles[declaration.property] = declaration.value }
    }
  }

  package func _styled(_ property: String, _ value: String) -> Text {
    var copy = self
    copy._textStyles.append(_TextStyleDeclaration(property: property, value: value))
    return copy
  }

  /// Renders a concatenation as one intrinsic text leaf. Nested
  /// concatenations stay inline spans inside the outermost leaf.
  @MainActor func _renderRuns(in context: _RenderContext, nested: Bool = false) -> _RenderNode {
    let node = _RenderNode.element("span")
    node.classes = ["rich-text-run"]
    if !nested {
      node.attributes["data-layout-kind"] = "intrinsic"
      node.attributes["data-layout-leaf"] = "text"
    }
    _applyTextStyles(to: node)
    if !nested { _applyLineLimit(context.environment.lineLimit, to: node) }
    // The line limit clamps the paragraph leaf, never its inline runs.
    var runContext = context
    runContext.environment.lineLimit = nil
    node.children = _textRuns.map { run in
      let child = run._textRuns.isEmpty ? run._render(in: runContext) : run._renderRuns(in: runContext, nested: true)
      guard let href = child.attributes["data-text-href"] else { return child }
      // A linked run (from AttributedString.link) is an anchor around its span. A link whose scheme could run
      // script (`javascript:`) stays plain text, as it would in SwiftUI.
      child.attributes["data-text-href"] = nil
      guard let safeHref = _safeURLAttribute(href) else { return child }
      let anchor = _RenderNode.element("a")
      anchor.attributes["href"] = safeHref
      // A link takes the tint, as SwiftUI paints it, and a tap is the environment's `openURL` action (which may
      // handle an in-document link itself) rather than the browser's navigation, so the default is prevented.
      anchor.styles["color"] = (runContext.environment.tint ?? Color._currentTint).cssValue
      let openURL = runContext.environment.openURL
      anchor.events["click"] = _EventHandler(name: "click", action: { openURL(URL(href)) }, preventsDefault: true)
      anchor.children = [child]
      return anchor
    }
    return node
  }
}

/// Deterministic declaration order keeps serialized HTML stable.
private func _sortedFontKeys(_ font: Font) -> [String] {
  var keys = Array(font.cssStyles.keys)
  var index = 1
  while index < keys.count {
    let value = keys[index]
    var position = index
    while position > 0 && keys[position - 1] > value {
      keys[position] = keys[position - 1]
      position -= 1
    }
    keys[position] = value
    index += 1
  }
  return keys
}

package func _textPixels(_ value: Double) -> String {
  guard value.isFinite else { return "0" }
  return Int64(exactly: value).map { String($0) } ?? String(value)
}
