@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// SwiftUI-shaped split views backed by the shared `Layout` engine.  The
/// browser host adds pointer/keyboard interaction for the divider metadata;
/// measurement and placement remain ordinary Swift layout operations.

internal enum _SplitAxis: String {
  case horizontal
  case vertical
}

@MainActor @preconcurrency
internal protocol _SplitLayoutMetadata {
  var _splitAxis: _SplitAxis { get }
  var _splitDividerThickness: CGFloat { get }
}

/// Horizontal split view, matching SwiftUI's macOS spelling and builder
/// shape. Children retain their normal Fiber keys; dividers use private keys
/// that cannot collide with application identity.
public nonisolated struct HSplitView<Content: View>: View {
  public typealias Body = Never
  private let content: Content

 public nonisolated init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    LayoutContainer(
      layout: _SplitLayout(axis: .horizontal),
      content: _SplitViewContent(axis: .horizontal, content: content)
    )._render(in: context)
  }
}

/// Vertical split view, matching SwiftUI's macOS spelling and builder shape.
public nonisolated struct VSplitView<Content: View>: View {
  public typealias Body = Never
  private let content: Content

 public nonisolated init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    LayoutContainer(
      layout: _SplitLayout(axis: .vertical),
      content: _SplitViewContent(axis: .vertical, content: content)
    )._render(in: context)
  }
}

private nonisolated struct _SplitViewContent<Content: View>: View {
  typealias Body = Never
  let axis: _SplitAxis
  let content: Content

  @MainActor func _render(in context: _RenderContext) -> _RenderNode {
    // The panes are placed with CSS, not by the layout host: every wrapper element of their content keeps its own CSS.
    var paneContext = context.child(_FiberKey("content"))
    paneContext._mergesLayoutLayers = false
    let rendered = content._render(in: paneContext)
    let children = _flattenLayoutChildren(rendered)
    let key = _splitViewKey(context)
    let store = context._splitViewStateStore
    let invalidationStore = context.stateStore
    let ownerToken = context._renderOwnerToken
    let paneCount = children.count
    let positions = _normalizedSplitPositions(store?.value(for: key), count: children.count)
    let encodedPositions = positions?.map { _layoutNumber(CGFloat($0)) }.joined(separator: ",")
    let fragment = _RenderNode.fragment()
    guard !children.isEmpty else { return fragment }
    var output: [_RenderNode] = []
    output.reserveCapacity(children.count * 2 - 1)
    for index in children.indices {
      let child = children[index]
      // Divider nodes are synthetic layout children. Give unkeyed content a
      // private stable key so inserting/removing a divider never shifts a
      // user's state-bearing child to a different Fiber path.
      if child.key == nil { child.key = _FiberKey("__split_item_\(index)") }
      child.attributes["data-split-item-index"] = String(index)
      child.attributes["data-split-key"] = key
      if let encodedPositions { child.attributes["data-split-positions"] = encodedPositions }
      // The browser host moves a divider within these limits without a round trip, so it reads each pane's extents here.
      let bounds = _splitConstraints(for: child, axis: axis)
      child.attributes["data-split-min"] = _layoutNumber(bounds.min)
      if bounds.max.isFinite { child.attributes["data-split-max"] = _layoutNumber(bounds.max) }
      output.append(child)
      guard index + 1 < children.count else { continue }
      let divider = _RenderNode.element("div")
      divider.key = _FiberKey("__split_divider_\(index)")
      divider.classes = ["pane-divider"]
      divider.attributes["data-split-divider-index"] = String(index)
      divider.attributes["data-split-key"] = key
      divider.attributes["data-split-axis"] = axis.rawValue
      divider.attributes["role"] = "separator"
      divider.attributes["tabindex"] = "0"
      divider.attributes["aria-orientation"] = axis == .horizontal ? "vertical" : "horizontal"
      divider.attributes["aria-label"] = axis == .horizontal ? "Resize columns" : "Resize rows"
      divider.attributes["aria-valuemin"] = "0"
      divider.attributes["aria-valuemax"] = "100"
      let defaultFraction = children.count > 0 ? 100.0 / Double(children.count) : 100
      let currentFraction = positions.flatMap { $0.indices.contains(index) ? $0[index] * 100 : nil } ?? defaultFraction * Double(index + 1)
      divider.attributes["aria-valuenow"] = _layoutNumber(CGFloat(currentFraction))
      divider.attributes["data-split-divider-size"] = "6"
      divider.styles["touch-action"] = "none"
      divider.styles["cursor"] = axis == .horizontal ? "col-resize" : "row-resize"
      divider.styles["background-color"] = "rgba(128,128,128,0.35)"
      divider.styles["z-index"] = "2"
      divider.styles["user-select"] = "none"
      if let encodedPositions { divider.attributes["data-split-positions"] = encodedPositions }
      // The host reports the positions a drag or a key press settled on. They are kept for the next render, which
      // places the panes from them; the owner renders again only when they changed.
      divider.events["split-positions"] = _EventHandler(name: "split-positions", action: { value in
        guard let next = _reportedSplitPositions(value, count: paneCount), next != store?.value(for: key) else { return }
        store?.setValue(next, for: key)
        if let ownerToken { invalidationStore._ownerObservationDidChange(ownerToken) }
      })
      output.append(divider)
    }
    fragment.children = output
    return fragment
  }
}

/// Shared layout algorithm for both split directions. Values are represented
/// as normalized item fractions so a divider remains stable across responsive
/// viewport changes; explicit frame min/ideal/max styles remain authoritative
/// pixel constraints during each placement pass.
internal nonisolated struct _SplitLayout: Layout, _SplitLayoutMetadata {
  var _swiftUIWebSplitAxisRaw: String? { axis.rawValue }
  var _swiftUIWebSplitDividerThickness: CGFloat { dividerThickness }
  typealias Cache = ()
  let axis: _SplitAxis
  let dividerThickness: CGFloat = 6

  var _splitAxis: _SplitAxis { axis }
  var _splitDividerThickness: CGFloat { dividerThickness }

  static var layoutProperties: LayoutProperties {
    var properties = LayoutProperties()
    properties.stackOrientation = .horizontal
    return properties
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
    let items = _itemIndices(subviews)
    let dividers = max(0, items.count - 1)
    let crossProposal = axis == .horizontal ? proposal.height : proposal.width
    let intrinsic = items.map { index in
      subviews[index].sizeThatFits(axis == .horizontal
        ? ProposedViewSize(width: nil, height: crossProposal)
        : ProposedViewSize(width: crossProposal, height: nil))
    }
    let intrinsicAxis = intrinsic.reduce(CGFloat(0)) { partial, size in
      partial + (axis == .horizontal ? size.width : size.height)
    } + CGFloat(dividers) * dividerThickness
    let intrinsicCross = intrinsic.map { axis == .horizontal ? $0.height : $0.width }.max() ?? 0
    let axisProposal = axis == .horizontal ? proposal.width : proposal.height
    let cross = crossProposal.flatMap { $0.isFinite ? $0 : nil } ?? intrinsicCross
    let extent = axisProposal.flatMap { $0.isFinite ? $0 : nil } ?? intrinsicAxis
    return axis == .horizontal ? CGSize(width: max(0, extent), height: max(0, cross)) : CGSize(width: max(0, cross), height: max(0, extent))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
    let itemIndices = _itemIndices(subviews)
    guard !itemIndices.isEmpty else { return }
    let dividerIndices = subviews.indices.filter { subviews[$0]._node.attributes["data-split-divider-index"] != nil }
    let available = max(0, (axis == .horizontal ? bounds.size.width : bounds.size.height) - CGFloat(dividerIndices.count) * dividerThickness)
    let cross = axis == .horizontal ? bounds.size.height : bounds.size.width
    let measured = itemIndices.map { index in
      subviews[index].sizeThatFits(axis == .horizontal
        ? ProposedViewSize(width: nil, height: cross)
        : ProposedViewSize(width: cross, height: nil))
    }
    var sizes = _initialSizes(subviews: subviews, itemIndices: itemIndices, measured: measured, available: available)
    let constraints = itemIndices.map { _constraints(for: subviews[$0]._node) }
    sizes = _clampAndRedistribute(sizes, constraints: constraints, available: available)

    var position = axis == .horizontal ? bounds.origin.x : bounds.origin.y
    for index in subviews.indices {
      if let itemOffset = itemIndices.firstIndex(of: index) {
        let extent = sizes[itemOffset]
        let size = axis == .horizontal ? CGSize(width: extent, height: cross) : CGSize(width: cross, height: extent)
        let point = axis == .horizontal ? CGPoint(x: position, y: bounds.origin.y) : CGPoint(x: bounds.origin.x, y: position)
        subviews[index].place(at: point, anchor: .topLeading, proposal: ProposedViewSize(width: size.width, height: size.height))
        position += extent
      } else if subviews[index]._node.attributes["data-split-divider-index"] != nil {
        let size = axis == .horizontal ? CGSize(width: dividerThickness, height: cross) : CGSize(width: cross, height: dividerThickness)
        let point = axis == .horizontal ? CGPoint(x: position, y: bounds.origin.y) : CGPoint(x: bounds.origin.x, y: position)
        subviews[index].place(at: point, anchor: .topLeading, proposal: ProposedViewSize(width: size.width, height: size.height))
        position += dividerThickness
      }
    }
  }

  private func _itemIndices(_ subviews: LayoutSubviews) -> [Int] {
    subviews.indices.filter { subviews[$0]._node.attributes["data-split-item-index"] != nil }
  }

  private func _initialSizes(subviews: LayoutSubviews, itemIndices: [Int], measured: [CGSize], available: CGFloat) -> [CGFloat] {
    let positions = subviews.first?._node.attributes["data-split-positions"]?.split(separator: ",").compactMap { Double($0) }
    if let positions, positions.count == itemIndices.count, positions.reduce(0, +) > 0 {
      let total = positions.reduce(0, +)
      return positions.map { available * CGFloat($0 / total) }
    }
    let ideals = itemIndices.enumerated().map { offset, index -> CGFloat in
      let measuredSize = axis == .horizontal ? measured[offset].width : measured[offset].height
      return _idealDimension(subviews[index]._node, axis: axis) ?? measuredSize
    }
    let total = ideals.reduce(0, +)
    guard total > 0 else { return Array(repeating: available / CGFloat(max(1, ideals.count)), count: ideals.count) }
    // Panes take their ideal extent; what is left over goes to the panes that can grow, the highest layoutPriority
    // first (a sidebar keeps its ideal width while the content pane takes the window), else it is shared out.
    if total < available {
      let growable = itemIndices.indices.filter { _constraints(for: subviews[itemIndices[$0]]._node).max.isInfinite }
      if !growable.isEmpty {
        let top = growable.map { subviews[itemIndices[$0]].priority }.max() ?? 0
        let receivers = growable.filter { subviews[itemIndices[$0]].priority == top }
        var sizes = ideals
        let share = (available - total) / CGFloat(receivers.count)
        for index in receivers { sizes[index] += share }
        return sizes
      }
    }
    return ideals.map { available * $0 / total }
  }

  private func _constraints(for node: _RenderNode) -> (min: CGFloat, max: CGFloat) {
    _splitConstraints(for: node, axis: axis)
  }

  private func _clampAndRedistribute(_ input: [CGFloat], constraints: [(min: CGFloat, max: CGFloat)], available: CGFloat) -> [CGFloat] {
    guard !input.isEmpty else { return [] }
    var output = zip(input, constraints).map { min($0.1.max, max($0.1.min, $0.0)) }
    for _ in 0..<input.count * 2 {
      let delta = available - output.reduce(0, +)
      if abs(delta) < 0.01 { break }
      let candidates = output.indices.filter { delta > 0 ? output[$0] < constraints[$0].max - 0.01 : output[$0] > constraints[$0].min + 0.01 }
      guard !candidates.isEmpty else { break }
      let share = delta / CGFloat(candidates.count)
      for index in candidates {
        output[index] = min(constraints[index].max, max(constraints[index].min, output[index] + share))
      }
    }
    return output
  }
}

@MainActor private func _splitViewKey(_ context: _RenderContext) -> String {
  context._fiberPath.isEmpty ? "<root-split>" : context._compactPathID
}

private func _normalizedSplitPositions(_ positions: [Double]?, count: Int) -> [Double]? {
  guard count > 0, let positions, !positions.isEmpty else { return nil }
  var values = Array(positions.prefix(count))
  if values.count < count { values.append(contentsOf: Array(repeating: 1, count: count - values.count)) }
  let total = values.reduce(0, +)
  guard total > 0 else { return nil }
  return values.map { $0 / total }
}

/// The minimum and maximum extent of a pane along the split's axis, from its frame styles.
private func _splitConstraints(for node: _RenderNode, axis: _SplitAxis) -> (min: CGFloat, max: CGFloat) {
  let minimum = _splitNumber(node.styles[axis == .horizontal ? "min-width" : "min-height"]) ?? 0
  let maximum = _splitNumber(node.styles[axis == .horizontal ? "max-width" : "max-height"]) ?? .infinity
  return (max(0, minimum), max(minimum, maximum))
}

/// The positions a browser host reports: one finite, non-negative value per pane, normalized to sum to 1.
private func _reportedSplitPositions(_ raw: String, count: Int) -> [Double]? {
  let values = raw.split(separator: ",", omittingEmptySubsequences: false).compactMap { Double($0) }
  guard values.count == count, values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
  return _normalizedSplitPositions(values, count: count)
}

private func _splitNumber(_ value: String?) -> CGFloat? {
  guard let value else { return nil }
  let compact = String(value.filter { !$0.isWhitespace })
  let raw = compact.hasSuffix("px") ? String(compact.dropLast(2)) : compact
  guard let number = Double(raw), number.isFinite else { return nil }
  return CGFloat(number)
}

private func _idealDimension(_ node: _RenderNode, axis: _SplitAxis) -> CGFloat? {
  let key = axis == .horizontal ? "width" : "height"
  if let value = node.styles[key], let parsed = _splitNumber(value) { return parsed }
  let semanticKey = axis == .horizontal ? "--ideal-width" : "--ideal-height"
  return _splitNumber(node.styles[semanticKey])
}
