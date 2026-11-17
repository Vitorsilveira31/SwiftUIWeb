/// Internal proposal metadata shared with the browser layout host. This is
/// renderer implementation detail; ordinary SwiftUI application APIs are unchanged.
package func _semanticNumber(_ value: Double) -> String {
  value.isInfinite ? "inf" : String(value)
}
package func _semanticAlignment(_ alignment: Alignment) -> _NodeValues {
  func scalar(_ value: String) -> String {
    if value == "start" || value == "flex-start" { return "0" }
    if value == "end" || value == "flex-end" { return "1" }
    return "0.5"
  }
  return ["data-align-x": scalar(alignment.horizontalValue),
          "data-align-y": scalar(alignment.verticalValue)]
}
func _semanticFrame(_ values: [String: Double?], _ alignment: Alignment) -> _NodeValues {
  var attributes = _semanticAlignment(alignment)
  attributes["data-layout-kind"] = "frame"
  for (name, value) in values { if let value { attributes["data-frame-" + name] = _semanticNumber(value) } }
  return attributes
}
/// CSS class carried by the wrapper a layout kind creates. Kinds named after a common word get a
/// distinctive class so the framework stylesheet cannot collide with application or library CSS.
func _semanticClass(_ kind: String) -> String {
  switch kind {
  case "aspect": return "aspect-box"
  case "background": return "backdrop-layer"
  case "frame": return "frame-box"
  case "grid": return "grid-layout"
  case "inset": return "inset-box"
  case "overlay": return "overlay-layer"
  default: return kind
  }
}
/// Create a real modifier boundary. The wrapper owns structural identity; the
/// original control retains its callbacks, task registrations and native tag.
/// Copying a button's listeners onto a div here used to dispatch refresh twice.
@discardableResult
package func _semanticWrap(_ node: _RenderNode, kind: String) -> _RenderNode {
  let child = node.cloneSharingChildren()
  child.key = nil
  child._renderOwnerToken = nil
  node.kind = .element("div")
  node.text = nil
  node.attributes = ["data-layout-kind": kind, "data-layout-schema": "1"]
  node.styles = .init()
  node.classes = [_semanticClass(kind)]
  node.children = [child]
  node.events = .init()
  node.taskRegistrations = []
  node.leafBindings = []
  node.lazyCollection = nil
  node._staticTemplateKey = nil
  node._layoutRender = nil
  node._tableCellRender = nil
  node._canvasCommands = []
  node._canvasFingerprint = nil
  node._dragSource = nil
  node._dropTarget = nil
  node._timeline = nil
  node.descriptor = "layout:" + kind
  return child
}

/// What a frame, padding, fixedSize or aspect-ratio wrapper built by hand holds for `content`. Such a wrapper has one
/// child; several views (a Section's header of two Texts) are stacked in a vstack of their own, leading aligned and with no
/// spacing, so that the CSS layout sees one child.
/// The modifiers do not need it: they wrap each view of a group on its own, as SwiftUI does.
@MainActor
func _semanticHeld(_ content: _RenderNode) -> [_RenderNode] {
  guard content.kind == .fragment else { return [content] }
  var views = 0, pending = [content]
  while let group = pending.popLast() {
    for child in group.children {
      if child.kind == .fragment { pending.append(child) } else if !child.isEmpty { views += 1 }
    }
  }
  guard views > 1 else { return [content] }
  let stack = _RenderNode.element("div")
  stack.classes = ["vstack"]
  for (name, value) in _semanticAlignment(Alignment(horizontal: .leading, vertical: .center)) { stack.attributes[name] = value }
  stack.attributes["data-layout-kind"] = "vstack"
  stack.attributes["data-layout-schema"] = "1"
  stack.attributes["data-layout-gap"] = _semanticNumber(0)
  stack.styles["align-items"] = "flex-start"
  stack.children = [content]
  return [stack]
}

// MARK: - Layers: one element for a run of frame, padding and fixedSize modifiers

/// A run of `frame`, `padding` and `fixedSize` modifiers used to make one element each, wrapping one another with a
/// single child and no look of their own: a `.padding(8).frame(width: 20)` was two `div`s. The run now shares one
/// element, which stands for the whole chain. The outermost modifier keeps the element's own layout attributes
/// (`data-layout-kind` and the `data-padding-*`, `data-frame-*` or `data-fixed-*` of that kind, as before); every
/// modifier inside it is a layer in `data-layout-wrap`, outermost first:
///
///     data-layout-kind="frame" data-frame-w="20" ... data-layout-wrap="padding;padding-top=8.0;padding-leading=8.0;..."
///
/// Each layer is its kind followed by `name=value` pairs, the names being the attribute names without `data-`. The
/// CSS layout (`CssLayout.chainPlan` in `Tools/css-layout.js`) folds the chain into the element's one box, so the layout is the one
/// the chain of elements gave, and the element is where the outermost wrapper was.
///
/// Only a wrapper that paints nothing and carries nothing (no event, key, task, accessibility attribute, background,
/// clip ...) takes another layer: whatever else is on it was meant for the box that wrapper has, not for the bigger one
/// of the layer outside it.
enum _SemanticLayers {
  static let wrapAttribute = "data-layout-wrap"
  /// The layout kinds that become layers.
  static func isLayerKind(_ kind: String) -> Bool { kind == "frame" || kind == "padding" || kind == "fixed" }
  /// Turned off by the tests that compare a chain of elements with the merged element.
  @MainActor static var isEnabled = true

  struct Layer {
    var kind: String
    /// `name=value` pairs, in the order they are written.
    var fields: [(name: String, value: String)]

    init(kind: String, semantic: _NodeValues) {
      self.kind = kind
      fields = []
      for name in semantic.keys.sorted() where name != "data-layout-kind" && name.hasPrefix("data-") {
        fields.append((String(name.dropFirst(5)), semantic[name] ?? ""))
      }
    }
    init(kind: String, fields: [(name: String, value: String)]) { self.kind = kind; self.fields = fields }

    func value(_ name: String) -> String? {
      for field in fields where field.name == name { return field.value }
      return nil
    }
    func number(_ name: String) -> Double? { value(name).flatMap { Double($0) } }
    /// The attributes this layer has on an element of its own.
    var attributes: _NodeValues {
      var out: _NodeValues = ["data-layout-kind": kind, "data-layout-schema": "1"]
      for field in fields { out["data-" + field.name] = field.value }
      return out
    }
    var encoded: String {
      var out = kind
      for field in fields { out += ";" + field.name + "=" + field.value }
      return out
    }
  }

  static func encode(_ layers: [Layer]) -> String {
    var out = ""
    for layer in layers { if !out.isEmpty { out += "|" }; out += layer.encoded }
    return out
  }

  static func decode(_ text: String) -> [Layer] {
    var layers: [Layer] = []
    for part in text.split(separator: "|") {
      let pieces = part.split(separator: ";", omittingEmptySubsequences: false)
      guard let kind = pieces.first else { continue }
      var fields: [(name: String, value: String)] = []
      for piece in pieces.dropFirst() {
        guard let equals = piece.firstIndex(of: "=") else { continue }
        fields.append((String(piece[piece.startIndex..<equals]), String(piece[piece.index(after: equals)...])))
      }
      layers.append(Layer(kind: String(kind), fields: fields))
    }
    return layers
  }

  private static func isLayerField(_ name: String) -> Bool {
    (name.hasPrefix("data-frame-") && name != "data-frame-alignment") || name.hasPrefix("data-padding-")
      || name.hasPrefix("data-fixed-") || name == "data-align-x" || name == "data-align-y"
  }

  /// The layer the element's own layout attributes describe: the outermost.
  static func standardLayer(of node: _RenderNode, kind: String) -> Layer {
    var own: _NodeValues = .init()
    for (name, value) in node.attributes where isLayerField(name) { own[name] = value }
    return Layer(kind: kind, semantic: own)
  }

  /// Every layer of the chain `node` stands for, outermost first. Empty for a node that is not a layer chain.
  static func layers(of node: _RenderNode) -> [Layer] {
    let attributes = node.attributes
    guard let kind = attributes["data-layout-kind"], isLayerKind(kind), attributes["data-layout-schema"] == "1"
    else { return [] }
    var out = [standardLayer(of: node, kind: kind)]
    if let text = attributes[wrapAttribute] { out.append(contentsOf: decode(text)) }
    return out
  }

  /// The layers inside the element's own, outermost first.
  static func innerLayers(of node: _RenderNode) -> [Layer] {
    guard let text = node.attributes[wrapAttribute] else { return [] }
    return decode(text)
  }

  // The styles a layer modifier leaves on its wrapper; and the ones a modifier applied to the wrapper afterwards can
  // leave without a difference between the box of the wrapper and the bigger box of the layers outside it (they
  // inherit, or are an opacity).
  private static let layoutStyles: Set<String> = [
    "padding", "padding-top", "padding-bottom", "padding-inline-start", "padding-inline-end",
    "width", "height", "min-width", "min-height", "max-width", "max-height",
    "display", "place-items", "margin-top", "margin-bottom", "margin-left", "margin-right", "margin-inline", "margin-block",
    "--ideal-width", "--ideal-height",
  ]
  private static let neutralStyles: Set<String> = [
    "color", "opacity", "font", "font-size", "font-weight", "font-family", "font-style", "font-variant",
    "font-variant-numeric", "font-feature-settings", "line-height", "letter-spacing", "text-align", "font-stretch",
    "font-optical-sizing", "text-decoration", "text-transform", "white-space",
  ]
  private static let layerClasses: Set<String> = ["frame-box", "padding", "fixed"]

  private static func isLayoutAttribute(_ name: String) -> Bool {
    name == "data-layout-kind" || name == "data-layout-schema" || name == wrapAttribute || name == "data-flexible-width"
      || name == "data-align-x" || name == "data-align-y"
      || name.hasPrefix("data-frame-") || name.hasPrefix("data-padding-") || name.hasPrefix("data-fixed-")
  }

  /// Whether `node` is nothing but the wrapper element `_semanticWrap` makes for a layer kind, so that a further layer
  /// can go on the same element.
  @MainActor static func isBareWrapper(_ node: _RenderNode) -> Bool {
    guard node._isBareLayoutWrapper else { return false }
    let attributes = node.attributes
    for name in attributes.keys where !isLayoutAttribute(name) { return false }
    guard let kind = attributes["data-layout-kind"], isLayerKind(kind), attributes["data-layout-schema"] == "1" else { return false }
    for name in node.styles.keys where !layoutStyles.contains(name) && !neutralStyles.contains(name) { return false }
    for name in node.classes where !layerClasses.contains(name) { return false }
    return true
  }

  enum Absorbed {
    /// `node` cannot take the layer: the caller wraps it.
    case no
    /// The layer is now the element's own, the old one went to `data-layout-wrap`; the caller applies the rest of the
    /// modifier (its attributes and styles) as it does for a new wrapper.
    case layered
    /// The padding was added to the one `node` has; there is nothing left to apply.
    case folded
  }

  /// Puts the modifier `kind` with `semantic` on `node` as the outermost layer of the chain it is, if it can.
  @MainActor static func absorb(kind: String, semantic: _NodeValues, into node: _RenderNode, allowsLayers: Bool = true) -> Absorbed {
    guard isEnabled, isLayerKind(kind), isBareWrapper(node), let ownKind = node.attributes["data-layout-kind"] else { return .no }
    let layer = Layer(kind: kind, semantic: semantic)
    let current = standardLayer(of: node, kind: ownKind)
    // Padding around padding is the padding of the sum, in every proposal: the outer one offers its content what is left
    // of the proposal, the inner one offers its content what is left of that, and the sizes add up. Only for insets that
    // are not negative (a negative one can leave a proposal below zero before the inner clamps it).
    if kind == "padding", ownKind == "padding", let sum = sumPadding(layer, current) {
      writePadding(sum, to: node)
      return .folded
    }
    // The wire has no escape: a value with one of its separators keeps the wrapper element.
    for field in current.fields where field.value.contains(";") || field.value.contains("|") || field.value.contains("=") { return .no }
    guard allowsLayers else { return .no }
    var inner = innerLayers(of: node)
    inner.insert(current, at: 0)
    // A chain that one CSS box cannot express keeps its wrapper elements, which CSS lays out one by one.
    guard isFoldable([layer] + inner) else { return .no }
    node.attributes[wrapAttribute] = encode(inner)
    // The element is the new outermost wrapper: it has its layout attributes, its layout styles and its class. What the
    // inner layers had of these is in the layer, and is derived again where it matters (`unfolded`).
    for name in Array(node.attributes.keys) where isLayerField(name) || name == "data-frame-alignment" { node.attributes.removeValue(forKey: name) }
    for name in layoutStyles { node.styles.removeValue(forKey: name) }
    // The classes name the kinds of the chain, the outermost first.
    let className = _semanticClass(kind)
    if let existing = node.classes.firstIndex(of: className) { node.classes.remove(at: existing) }
    node.classes.insert(className, at: 0)
    node._staticTemplateKey = nil
    return .layered
  }

  /// Whether the CSS layout can lay `layers` (outermost first, the element's own layer first) out in the one box of their
  /// element. The conditions are those under which `chainPlan` (`Tools/css-layout.js`) finds no
  /// plan: more than one box on an axis (a fixed, fixedSize or min/max frame that nothing fills), a layer other than a
  /// padding inside a padding that is inside a box, and a filling minimum that overflows the fixed frame holding it.
  static func isFoldable(_ layers: [Layer]) -> Bool {
    guard let outer = layers.first else { return true }
    func sized(_ layer: Layer, _ axis: String) -> Bool {
      layer.value("frame-" + axis) != nil || layer.value("frame-min-" + axis) != nil || layer.value("frame-max-" + axis) != nil
    }
    // The padding between the box and the first box inside it, per edge: a negative sum is not padding (a margin of the child).
    var padding = (top: 0.0, leading: 0.0, bottom: 0.0, trailing: 0.0), boxes: [Layer] = [], insidePadding = false
    func pad(_ layer: Layer) {
      padding.top += layer.number("padding-top") ?? 0; padding.leading += layer.number("padding-leading") ?? 0
      padding.bottom += layer.number("padding-bottom") ?? 0; padding.trailing += layer.number("padding-trailing") ?? 0
    }
    if outer.kind == "padding" { pad(outer) }
    for layer in layers.dropFirst() {
      if layer.kind == "padding" {
        if boxes.isEmpty { pad(layer) } else { insidePadding = true }
        continue
      }
      if insidePadding { return false }
      if layer.kind == "frame" && !sized(layer, "w") && !sized(layer, "h") { continue }
      boxes.append(layer)
    }
    let insets = [("w", max(0, padding.leading) + max(0, padding.trailing)), ("h", max(0, padding.top) + max(0, padding.bottom))]
    for (axis, inset) in insets {
      // The entries of the boxes on this axis, as `chainPlan` has them: the minimum of a filling or floor frame, and
      // whether the entry is a box of its own (a filling frame, and a frame with a minimum only around another box, is not).
      var entries: [(box: Bool, minimum: Double?, floor: Bool)] = []
      for layer in boxes {
        if layer.kind == "fixed" { if layer.value("fixed-" + (axis == "w" ? "x" : "y")) != "false" { entries.append((true, nil, false)) }; continue }
        let minimum = layer.number("frame-min-" + axis), maximum = layer.number("frame-max-" + axis)
        if layer.number("frame-" + axis) != nil { entries.append((true, nil, false)) }
        else if maximum == .infinity { entries.append((false, minimum, false)) }
        else if minimum != nil || maximum != nil { entries.append((true, minimum, maximum == nil)) }
      }
      var boxed = 0
      for (index, entry) in entries.enumerated() {
        let floor = entry.floor && entries[(index + 1)...].contains { $0.box }
        if entry.box && !floor { boxed += 1 }
      }
      if boxed > 1 { return false }
      let minimum = max(0, entries.compactMap { $0.minimum }.max() ?? 0)
      if boxed == 0, minimum != 0, outer.kind == "frame", let fixed = outer.number("frame-" + axis), minimum + inset > fixed { return false }
    }
    return true
  }

  /// The padding of `outer` around `inner`, or nil when an inset is negative or not a number.
  private static func sumPadding(_ outer: Layer, _ inner: Layer) -> Layer? {
    var fields: [(name: String, value: String)] = []
    for edge in ["top", "leading", "bottom", "trailing"] {
      let name = "padding-" + edge
      let a = outer.number(name), b = inner.number(name)
      if a == nil && b == nil { continue }
      let sum = (a ?? 0) + (b ?? 0)
      if (a ?? 0) < 0 || (b ?? 0) < 0 || !sum.isFinite { return nil }
      fields.append((name, String(sum)))
    }
    return Layer(kind: "padding", fields: fields)
  }

  /// Writes `padding` as the padding of `node`, attributes and styles the way `_paddingModifier` makes them.
  @MainActor private static func writePadding(_ padding: Layer, to node: _RenderNode) {
    for edge in ["top", "leading", "bottom", "trailing"] { node.attributes.removeValue(forKey: "data-padding-" + edge) }
    for key in ["padding", "padding-top", "padding-bottom", "padding-inline-start", "padding-inline-end"] { node.styles.removeValue(forKey: key) }
    var css: _NodeValues = .init()
    for field in padding.fields {
      node.attributes["data-" + field.name] = field.value
      guard let amount = Double(field.value) else { continue }
      let pixels = (Int64(exactly: amount).map { String($0) } ?? String(amount)) + "px"
      switch field.name {
      case "padding-top": css["padding-top"] = pixels
      case "padding-leading": css["padding-inline-start"] = pixels
      case "padding-bottom": css["padding-bottom"] = pixels
      default: css["padding-inline-end"] = pixels
      }
    }
    if css.count == 4, Set(css.values).count == 1, let pixels = css.values.first { node.styles["padding"] = pixels }
    else { for (key, value) in css { node.styles[key] = value } }
  }
}

extension _RenderNode {
  /// True for a node with nothing attached to it but layout attributes, styles and classes (which the caller checks):
  /// no key, text, event, task, binding or any other renderer metadata, so that another layer on it changes nothing
  /// that was meant for it.
  @MainActor var _isBareLayoutWrapper: Bool {
    if _selfPending != nil { _resolveSelf() }
    guard _attributeJob == nil, case .element("div") = _sKind, _sText == nil, _sKey == nil,
          _sEvents.isEmpty, _sTaskRegistrations.isEmpty, _sLeafBindings.isEmpty, _sSecureValue == nil,
          _sLazyCollection == nil, _sHoverProbe == nil, _sLayoutValues.isEmpty, _sLayoutRender == nil,
          _sLayoutAlignmentGuides.isEmpty, _sLayoutExplicitHorizontalAlignment == nil, _sLayoutExplicitVerticalAlignment == nil,
          _sTagIdentity == nil, _sPickerSelectionValue == nil, _sTableCellRender == nil, _sTableColumnSort == nil,
          _sTableRowValue == nil, _sCanvasCommands.isEmpty, _sCanvasFingerprint == nil, _sDragSource == nil,
          _sDropTarget == nil, _sTimeline == nil, _sDomView == nil, _sOnChangeCount == 0
    else { return false }
    return true
  }
}

// MARK: - The chain an element stands for, as elements

extension _SemanticLayers {
  /// `node` with the layers inside it as the wrapper elements they stand for, innermost around the node's children, for
  /// the code that measures render nodes (a custom `Layout` measures its subviews in Swift, from their styles). A node
  /// that is not a chain is returned as it is.
  static func unfolded(_ node: _RenderNode) -> _RenderNode {
    let inner = innerLayers(of: node)
    guard !inner.isEmpty else { return node }
    var content = node.children
    for layer in inner.reversed() {
      let wrapper = _RenderNode.element("div")
      wrapper.attributes = layer.attributes
      wrapper.styles = styles(of: layer)
      wrapper.classes = [_semanticClass(layer.kind)]
      wrapper.children = content
      content = [wrapper]
    }
    let outer = node.cloneSharingChildren()
    outer.attributes.removeValue(forKey: wrapAttribute)
    outer.children = content
    return outer
  }

  private static func pixels(_ value: Double) -> String {
    if value.isInfinite { return "100%" }
    if value.isNaN { return "auto" }
    return (Int64(exactly: value).map { String($0) } ?? String(value)) + "px"
  }

  /// The sizing styles the modifier of `layer` gave its wrapper (`_frameModifier`, `_fixedSizeModifier`): the ones that
  /// the measurement of a node reads. The padding of a layer is in its attributes. `SemanticLayerTests` compares them
  /// with what the modifiers make.
  static func styles(of layer: Layer) -> _NodeValues {
    var styles: _NodeValues = .init()
    switch layer.kind {
    case "fixed":
      if layer.value("fixed-x") == "true" { styles["width"] = "max-content" }
      if layer.value("fixed-y") == "true" { styles["height"] = "max-content" }
    case "frame":
      if let value = layer.number("frame-min-w") { styles["min-width"] = pixels(value) }
      if let value = layer.number("frame-ideal-w") { styles["width"] = pixels(value) }
      if let value = layer.number("frame-w") { styles["width"] = pixels(value) }
      if let value = layer.number("frame-max-w") {
        styles["max-width"] = pixels(value)
        if layer.value("frame-w") == nil { styles["width"] = "100%" }
      }
      if let value = layer.number("frame-min-h") { styles["min-height"] = pixels(value) }
      if let value = layer.number("frame-ideal-h") { styles["height"] = pixels(value) }
      if let value = layer.number("frame-h") { styles["height"] = pixels(value) }
      if let value = layer.number("frame-max-h") {
        styles["max-height"] = pixels(value)
        if layer.value("frame-h") == nil && value.isInfinite { styles["height"] = "100%" }
      }
    default: break
    }
    return styles
  }
}
