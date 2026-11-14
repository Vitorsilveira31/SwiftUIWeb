/// `.pickerStyle(.segmented)`: a row of segments in a capsule track with the
/// selected segment highlighted, like UISegmentedControl.
///
/// Accessibility follows the WAI-ARIA radio-group pattern: the track is a
/// `radiogroup` named by the picker title, each segment is a `radio` button
/// with `aria-checked`, only the selected segment is in the tab order, and
/// the browser host moves the selection with the arrow/Home/End keys. The
/// title is not drawn (iOS never draws a segmented picker's label).
struct _SegmentedPickerOption {
  let label: String
  let content: _RenderNode
  let isSelected: () -> Bool
  let select: @MainActor () -> Void
}

/// The container of a segmented picker, before its segments are known.
@MainActor func _segmentedPickerNode(title: String, context: _RenderContext) -> _RenderNode {
  let node = _RenderNode.element("div")
  node.classes = ["picker-control", "segmented-picker"]
  node.attributes["data-control-kind"] = "picker"
  node.attributes["data-picker-style"] = "segmented"
  node.attributes["role"] = "radiogroup"
  if !title.isEmpty { _AccessibilityBackend.setLabel(title, on: node) }
  if let tint = context.environment.tint { node.styles["--tint-color"] = tint.cssValue }
  if !context.environment.isEnabled { node.attributes["aria-disabled"] = "true" }
  return node
}

/// The segments of a segmented picker.
@MainActor func _segmentedPickerChildren(
  options: [_SegmentedPickerOption],
  sourceID: _StateSourceID?,
  context: _RenderContext
) -> [_RenderNode] {
  let isEnabled = context.environment.isEnabled
  return options.map { option in
    let segment = _RenderNode.element("button")
    segment.attributes["type"] = "button"
    segment.attributes["role"] = "radio"
    segment.classes = ["segment-item"]
    let selected = option.isSelected()
    segment.attributes["aria-checked"] = selected ? "true" : "false"
    segment.attributes["tabindex"] = selected ? "0" : "-1"
    if let sourceID {
      segment.leafBindings.append(_LeafBindingDescriptor(sourceID: sourceID, operation: .attribute("aria-checked"), value: { option.isSelected() ? "true" : "false" }))
      segment.leafBindings.append(_LeafBindingDescriptor(sourceID: sourceID, operation: .attribute("tabindex"), value: { option.isSelected() ? "0" : "-1" }))
    }
    if isEnabled {
      segment.events["click"] = _EventHandler(name: "click", action: option.select)
    } else {
      segment.attributes["disabled"] = "disabled"
    }
    // `Option` renders a native <option>; draw its text instead. Tagged
    // Text/Image/Label content keeps its own rendering (icons included).
    if case .element(let tag) = option.content.kind, tag.lowercased() == "option" {
      segment.children = [.text(option.label)]
    } else {
      segment.children = [option.content]
    }
    return segment
  }
}
