/// Toggle presentation selected by `.toggleStyle(_:)`.
///
/// - `.switch` / `.automatic`: a native checkbox with `role="switch"`.
/// - `.checkbox`: a native checkbox (square box before the label).
/// - `.button`: a button whose selected state (`aria-pressed`) follows the
///   binding; clicking it flips the value.
///
/// `.labelsHidden()` removes the visible label of switch and checkbox toggles
/// while the label text stays the control's accessibility label, as in
/// SwiftUI. A button toggle's label is its content and stays visible.

private enum ToggleStyleEnvironmentKey: EnvironmentKey { static let defaultValue = "automatic" }

extension EnvironmentValues {
  @_spi(Renderer) public var _toggleStyle: String {
    get { self[ToggleStyleEnvironmentKey.self] }
    set { self[ToggleStyleEnvironmentKey.self] = newValue }
  }
}

@MainActor func _renderToggle(isOn: Binding<Bool>, labelNode: _RenderNode, context: _RenderContext) -> _RenderNode {
  let style = context.environment._toggleStyle
  let labelText = _toggleAccessibilityText(labelNode) ?? "Toggle"
  if style == "button" { return _renderButtonToggle(isOn: isOn, labelNode: labelNode, labelText: labelText, context: context) }

  let node = _RenderNode.element("label")
  node.classes = ["toggle-switch"]
  node.attributes["data-control-kind"] = "toggle"
  node.attributes["data-toggle-style"] = style == "checkbox" ? "checkbox" : "switch"
  let input = _RenderNode.element("input")
  input.attributes["type"] = "checkbox"
  if style == "checkbox" {
    input.classes = ["toggle-checkbox"]
  } else {
    input.classes = ["check-input"]
    input.attributes["role"] = "switch"
  }
  _AccessibilityBackend.setLabel(labelText, on: input)
  _AccessibilityBackend.setState("checked", isOn.wrappedValue ? "true" : "false", on: input)
  input.attributes["checked"] = isOn.wrappedValue ? "checked" : nil
  if let sourceID = isOn._sourceID {
    input.leafBindings.append(_LeafBindingDescriptor(sourceID: sourceID, operation: .property("checked"), value: { isOn.wrappedValue ? "true" : "false" }))
    input.leafBindings.append(_LeafBindingDescriptor(sourceID: sourceID, operation: .attribute("aria-checked"), value: { isOn.wrappedValue ? "true" : "false" }))
    input.leafBindings.append(_LeafBindingDescriptor(sourceID: sourceID, operation: .attribute("checked"), value: { isOn.wrappedValue ? "checked" : "" }))
  }
  if context.environment.isEnabled {
    // The action fallback keeps Fiber tests and non-value hosts compatible,
    // while BrowserIO uses the actual checked value. Toggling blindly can
    // diverge when a browser event is replayed after a state update.
    input.events["change"] = _EventHandler(
      name: "change",
      action: { isOn.wrappedValue.toggle() },
      valueAction: { raw in
        // Concrete Boolean vocabulary: Embedded Swift has no general
        // scalar-to-generic cast.
        switch raw.lowercased() {
        case "true", "1", "yes": isOn.wrappedValue = true
        case "false", "0", "no": isOn.wrappedValue = false
        default: break
        }
      }
    )
    _applyKeyboardShortcut(context, to: input)
  } else {
    input.attributes["disabled"] = "disabled"
    input.attributes["aria-disabled"] = "true"
  }
  if context.environment._labelsHidden {
    node.attributes["data-labels-hidden"] = "true"
    node.children = [input]
  } else if style == "checkbox" {
    node.children = [input, labelNode]
  } else {
    // A switch row reads label first and the switch at the trailing edge, filling its row, as in SwiftUI.
    let spacer = _RenderNode.element("div")
    spacer.classes = ["flex-spacer"]
    spacer.attributes["data-layout-kind"] = "spacer"
    spacer.attributes["data-layout-schema"] = "1"
    spacer.attributes["data-spacer-min"] = "12"
    node.classes.append("hstack")
    node.attributes["data-layout-kind"] = "hstack"
    node.attributes["data-layout-schema"] = "1"
    node.attributes["data-layout-gap"] = _semanticNumber(0)
    node.attributes["data-align-x"] = "0.5"
    node.attributes["data-align-y"] = "0.5"
    // The switch is a fixed 44 x 24 control; measured as an empty native input it would report a couple of points.
    input.attributes["data-layout-kind"] = "size"
    input.attributes["data-layout-schema"] = "1"
    input.attributes["data-size-w"] = "44"
    input.attributes["data-size-h"] = "24"
    node.children = [labelNode, spacer, input]
  }
  return node
}

@MainActor private func _renderButtonToggle(isOn: Binding<Bool>, labelNode: _RenderNode, labelText: String, context: _RenderContext) -> _RenderNode {
  let node = _RenderNode.element("button")
  node.attributes["type"] = "button"
  node.attributes["data-control-kind"] = "toggle"
  node.attributes["data-toggle-style"] = "button"
  node.classes = [
    "push-button", "toggle-button",
    "button-\(context.environment.buttonStyle.rawValue)",
    "control-\(context.environment.controlSize.rawValue)"
  ]
  node.attributes["aria-pressed"] = isOn.wrappedValue ? "true" : "false"
  if isOn.wrappedValue { node.attributes["data-selected"] = "true" }
  if let tint = context.environment.tint { node.styles["--tint-color"] = tint.cssValue }
  if labelNode.isEmpty { _AccessibilityBackend.setLabel(labelText, on: node) }
  if context.environment.isEnabled {
    node.events["click"] = _EventHandler(name: "click", action: { isOn.wrappedValue.toggle() })
    _applyKeyboardShortcut(context, to: node)
  } else {
    node.attributes["disabled"] = "disabled"
    node.attributes["aria-disabled"] = "true"
  }
  node.children = labelNode.isEmpty ? [] : [labelNode]
  return node
}

func _toggleAccessibilityText(_ node: _RenderNode) -> String? {
  if let label = node.attributes["aria-label"], !label.isEmpty { return label }
  if let text = node.text { return text }
  let values = node.children.compactMap(_toggleAccessibilityText)
  // Rich Text runs already carry their own spacing.
  let separator = node.attributes["data-layout-leaf"] == "text" ? "" : " "
  return values.isEmpty ? nil : values.joined(separator: separator)
}
