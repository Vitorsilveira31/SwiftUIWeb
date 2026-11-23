@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

/// Commonly used by SwiftUI layouts that animate two independent parameters.
public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>: VectorArithmetic {
  public var first: First
  public var second: Second
  public init(_ first: First, _ second: Second) {
    self.first = first
    self.second = second
  }
  public static var zero: AnimatablePair<First, Second> { AnimatablePair(.zero, .zero) }
  public static func + (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> {
    AnimatablePair(lhs.first + rhs.first, lhs.second + rhs.second)
  }
  public static func - (lhs: AnimatablePair<First, Second>, rhs: AnimatablePair<First, Second>) -> AnimatablePair<First, Second> {
    AnimatablePair(lhs.first - rhs.first, lhs.second - rhs.second)
  }
  public var magnitudeSquared: Double { first.magnitudeSquared + second.magnitudeSquared }
  public mutating func scale(by rhs: Double) {
    first.scale(by: rhs)
    second.scale(by: rhs)
  }
}

public extension View {
  /// Stores a value for the nearest custom layout. Values are read from a
  /// `LayoutSubview` using `subview[MyKey.self]`.
  nonisolated func layoutValue<K: LayoutValueKey>(key: K.Type, value: K.Value) -> some View {
    _modified(LayoutValueModifier(key: key, value: value))
  }

  @preconcurrency nonisolated func alignmentGuide(_ guide: HorizontalAlignment, computeValue: @escaping @Sendable (ViewDimensions) -> CGFloat) -> some View {
    _modified(AlignmentGuideModifier(key: guide.cssValue, computeValue: computeValue))
  }

  @preconcurrency nonisolated func alignmentGuide(_ guide: VerticalAlignment, computeValue: @escaping @Sendable (ViewDimensions) -> CGFloat) -> some View {
    _modified(AlignmentGuideModifier(key: guide.cssValue, computeValue: computeValue))
  }
}

package nonisolated struct LayoutValueModifier<K: LayoutValueKey>: ViewModifier {
  package let key: K.Type
  package let value: K.Value

  package init(key: K.Type, value: K.Value) {
    self.key = key; self.value = value
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node._layoutValues[ObjectIdentifier(key)] = _LayoutValueBox(value)
  }
}

package nonisolated struct AlignmentGuideModifier: ViewModifier {
  fileprivate let key: String
  fileprivate let computeValue: (ViewDimensions) -> CGFloat

  fileprivate init(key: String, computeValue: @escaping (ViewDimensions) -> CGFloat) {
    self.key = key; self.computeValue = computeValue
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node._layoutAlignmentGuides[key] = computeValue
  }
}

public extension Layout {
  /// SwiftUI's `MyLayout { ... }` spelling.
 @_disfavoredOverload func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    LayoutContainer(layout: self, content: content())
  }
}

package nonisolated struct LayoutContainer<L: Layout, Content: View>: View, _OwnerBoundaryContent {
  package typealias Body = Never
  package let layout: L
  package let content: Content
  @State(memberID: 3649057290) private var proposalStore = _LayoutProposalStore()

  package init(layout: L, content: Content) { self.layout = layout; self.content = content }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    #if hasFeature(Embedded)
    // A user-defined Layout runs in Swift, but its parent negotiates in the
    // host. The host reports the proposal it offered and this layout, as its
    // own render owner, re-evaluates with it. Built-in layouts negotiate in the browser's CSS layout.
    if layout._swiftUIWebSemanticLayout == nil {
      return AnyView(_ownerBoundaryOf: self)._render(in: context)
    }
    #endif
    return _renderLayout(in: context)
  }

  @MainActor package func _renderOwnerBoundary(in context: _RenderContext) -> _RenderNode { _renderLayout(in: context) }

  @MainActor private func _renderLayout(in context: _RenderContext) -> _RenderNode {
    let previousScope = StateRuntime.scope
    StateRuntime.scope = StateScope(context: context, viewTag: "LayoutContainer")
    defer { StateRuntime.scope = previousScope }
    var contentContext = context.child(_FiberKey("layout-content"))
    // A GeometryReader among the subviews draws first for a guess, until the page has measured it: the size this layout is
    // offered is the nearest one (the enclosing reader's, the window, was Food Truck's whole page for a donut in a tile).
    #if hasFeature(Embedded)
    let offered = _hostLayoutProposal(context._layoutProposal ?? .unspecified, store: proposalStore)
    #else
    let offered = context._layoutProposal ?? .unspecified
    #endif
    if let width = offered.width, let height = offered.height, width.isFinite, height.isFinite, width > 0, height > 0 {
      contentContext.environment._geometryHint = CGSize(width: width, height: height)
    }
    #if hasFeature(Embedded)
    // A built-in layout only collects its children, so a deep render hands them to the loop that drives the
    // pass instead of recursing (see `_RenderStaging`). A layout that runs in Swift needs them to measure.
    if _RenderStaging.wantsDeferral, let semantic = layout._swiftUIWebSemanticLayout {
      let wrapper = _semanticLayoutWrapper(semantic, children: [])
      wrapper._deferChildren(_RenderStaging.defer_(content, context: contentContext))
      return wrapper
    }
    #endif
    let rendered = content._render(in: contentContext)
    let childNodes = _flattenLayoutChildren(rendered)
    #if hasFeature(Embedded)
    if let semantic = layout._swiftUIWebSemanticLayout {
      // User-defined Layout still executes Swift below. Built-in layouts,
      // including a built-in erased through AnyLayout, negotiate in the browser's CSS layout.
      return _semanticLayoutWrapper(semantic, children: childNodes)
    }
    let store: _LayoutProposalStore? = proposalStore
    #else
    // Off Embedded the proposal store is never read, so its @State slot stays untouched.
    let store: _LayoutProposalStore? = nil
    #endif
    let subviews = _makeLayoutSubviews(childNodes, store: store)
    let cacheKey = _layoutCacheKey(context: context)
    let layoutIdentifier = _layoutIdentifier(layout)
    var cache: L.Cache
    #if hasFeature(Embedded)
    // Embedded Swift has no dynamic casts. Cache reuse is an optimization, so
    // construct the typed cache directly and keep rendering semantics intact.
    cache = layout.makeCache(subviews: subviews)
    #else
    if let store = context._layoutCacheStore,
       let retained = store.value(for: cacheKey, identifier: layoutIdentifier) as? L.Cache {
      cache = retained
    } else {
      cache = layout.makeCache(subviews: subviews)
    }
    #endif
    layout.updateCache(&cache, subviews: subviews)
    let layoutSpacing = layout.spacing(subviews: subviews, cache: &cache)
    var proposal = context._layoutProposal ?? .unspecified
    #if hasFeature(Embedded)
    // What the host offered this layout (after every enclosing frame, aspect
    // ratio and stack allocated space) replaces the inherited root proposal.
    proposal = _hostLayoutProposal(proposal, store: proposalStore)
    #endif
    let measured = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    let width = max(0, measured.width.isFinite ? measured.width : 0)
    let height = max(0, measured.height.isFinite ? measured.height : 0)
    let bounds = CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: width, height: height))
    let explicitLeading = layout.explicitAlignment(of: .leading, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    let explicitTrailing = layout.explicitAlignment(of: .trailing, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    let explicitTop = layout.explicitAlignment(of: .top, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    let explicitBottom = layout.explicitAlignment(of: .bottom, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    context._layoutCacheStore?.setValue(cache, for: cacheKey, identifier: layoutIdentifier)
    #if hasFeature(Embedded)
    let layoutType = "layout"
    let layoutAnimatable = ""
    #else
    let layoutType = _swiftUIWebTypeName(L.self)
    // Keep the current animatable value on the semantic layout boundary. The
    // animation modifier/host can interpolate changed placement styles while
    // the layout itself remains authoritative for every calculated frame.
    let layoutAnimatable = _layoutAnimatableDescription(layout)
    #endif
    // Built after the last cache mutation so the closures see the committed cache.
    let pass = _LayoutPass(
      width: width,
      height: height,
      explicitLeading: explicitLeading,
      explicitTrailing: explicitTrailing,
      explicitTop: explicitTop,
      explicitBottom: explicitBottom,
      spacing: layoutSpacing,
      splitAxis: layout._swiftUIWebSplitAxisRaw,
      splitDividerThickness: layout._swiftUIWebSplitDividerThickness,
      grid: _layoutGridConfiguration(layout),
      layoutType: layoutType,
      layoutAnimatable: layoutAnimatable,
      render: { proposal in
        var next = context
        next._layoutProposal = proposal
        return self._render(in: next)
      },
      // Keep arbitrary custom guides available to an enclosing Layout. The
      // closures snapshot the current semantic bounds/proposal and use a copy
      // of the retained cache so a dimensions query cannot mutate the cache
      // that was just committed for this render pass.
      explicitHorizontal: { guide in
        var queryCache = cache
        return layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &queryCache)
      },
      explicitVertical: { guide in
        var queryCache = cache
        return layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &queryCache)
      }
    )
    return _assembleLayoutWrapper(pass, childNodes: childNodes, subviews: subviews, context: context, store: store)
  }
}

/// The type-independent outputs of one layout pass. Non-generic, so the wrapper
/// assembly is compiled once rather than per `Layout`/`Content` specialization.
fileprivate struct _LayoutPass {
  var width: CGFloat
  var height: CGFloat
  var explicitLeading: CGFloat?
  var explicitTrailing: CGFloat?
  var explicitTop: CGFloat?
  var explicitBottom: CGFloat?
  var spacing: ViewSpacing
  var splitAxis: String?
  var splitDividerThickness: CGFloat
  var grid: _GridLayoutConfiguration?
  var layoutType: String
  var layoutAnimatable: String
  var render: (ProposedViewSize) -> _RenderNode
  var explicitHorizontal: (HorizontalAlignment) -> CGFloat?
  var explicitVertical: (VerticalAlignment) -> CGFloat?
}

@MainActor private func _makeLayoutSubviews(_ childNodes: [_RenderNode], store: _LayoutProposalStore?) -> LayoutSubviews {
  LayoutSubviews(childNodes.enumerated().map { index, node in
    let storage = _LayoutSubviewStorage(node: node, id: index, initialSize: _LayoutNodeMeasurer.measure(node, proposal: .unspecified))
    #if hasFeature(Embedded)
    if let store {
      storage.hostSizes = store.measured[index] ?? []
      store.renderedMeasured[index] = store.measured[index]
    }
    #endif
    return LayoutSubview(storage: storage)
  })
}

@MainActor private func _assembleLayoutWrapper(
  _ pass: _LayoutPass,
  childNodes: [_RenderNode],
  subviews: LayoutSubviews,
  context: _RenderContext,
  store: _LayoutProposalStore?
) -> _RenderNode {
  let wrapper = _RenderNode.element("div")
  wrapper.classes = ["layout-box"]
  wrapper.styles["position"] = "relative"
  wrapper.styles["box-sizing"] = "border-box"
  wrapper.styles["width"] = "\(_layoutNumber(pass.width))px"
  wrapper.styles["height"] = "\(_layoutNumber(pass.height))px"
  wrapper.attributes["data-layout-content-width"] = _layoutNumber(pass.width)
  wrapper.attributes["data-layout-content-height"] = _layoutNumber(pass.height)
  if let splitAxis = pass.splitAxis {
    wrapper.classes.append("split-pane")
    wrapper.styles["overflow"] = "hidden"
    wrapper.styles["contain"] = "layout paint"
    wrapper.attributes["data-split-axis"] = splitAxis
    wrapper.attributes["data-split-divider-size"] = _layoutNumber(pass.splitDividerThickness)
    if let first = childNodes.first {
      if let key = first.attributes["data-split-key"] { wrapper.attributes["data-split-key"] = key }
      if let positions = first.attributes["data-split-positions"] { wrapper.attributes["data-split-positions"] = positions }
    }
    wrapper.attributes["data-split-item-count"] = String(childNodes.filter { $0.attributes["data-split-item-index"] != nil }.count)
    wrapper.attributes["data-split-divider-count"] = String(childNodes.filter { $0.attributes["data-split-divider-index"] != nil }.count)
  }
  wrapper._layoutRender = pass.render
  #if hasFeature(Embedded)
  wrapper.attributes["data-layout-proposal"] = "true"
  if let store {
    // The proposal this pass was laid out for, as the page reported it (empty where it reported none): the page sends its
    // proposal again when this is not what it measures, as a layout whose state was made again (its element kept) had
    // gone back to the proposal it inherits and the page, which had already sent its own, never sent it again.
    func axis(_ value: CGFloat?) -> String { value.map { _layoutNumber($0) } ?? "" }
    wrapper.attributes["data-layout-offered"] = axis(store.rendered.width) + "," + axis(store.rendered.height)
    let ownerToken = context._renderOwnerToken
    let invalidationStore = context.stateStore
    wrapper.events["layoutproposal"] = _EventHandler(name: "layoutproposal", action: { rawValue in
      let next = _parseProposal(rawValue)
      // Sent again although known (`data-layout-offered`): laid out for another, it is laid out again.
      guard next != store.reported || next != store.rendered else { return }
      store.reported = next
      if next != store.rendered, let ownerToken { invalidationStore._ownerObservationDidChange(ownerToken) }
    })
    wrapper.events["layoutsizes"] = _EventHandler(name: "layoutsizes", action: { rawValue in
      // "proposal:size|proposal:size;proposal:size..." in subview order: the size at the proposal the subview was placed with,
      // then at each other proposal the layout asked it about (`data-layout-asks`), each pair as "width,height".
      var next: [Int: [(proposal: ProposedViewSize, size: CGSize)]] = .init()
      var index = 0
      for entry in rawValue.split(separator: ";", omittingEmptySubsequences: false) {
        var sizes: [(proposal: ProposedViewSize, size: CGSize)] = []
        for measurement in entry.split(separator: "|") {
          let parts = measurement.split(separator: ":", omittingEmptySubsequences: false)
          guard parts.count == 2 else { continue }
          let size = _parseProposal(String(parts[1]))
          if let width = size.width, let height = size.height {
            sizes.append((_parseProposal(String(parts[0])), CGSize(width: width, height: height)))
          }
        }
        if !sizes.isEmpty { next[index] = sizes }
        index += 1
      }
      typealias Sizes = [Int: [(proposal: ProposedViewSize, size: CGSize)]]
      func same(_ a: Sizes, _ b: Sizes) -> Bool {
        guard a.count == b.count else { return false }
        for (key, values) in a {
          guard let others = b[key], others.count == values.count else { return false }
          for (value, other) in zip(values, others) {
            guard other.proposal == value.proposal,
                  abs(other.size.width - value.size.width) < 0.25, abs(other.size.height - value.size.height) < 0.25 else { return false }
          }
        }
        return true
      }
      guard !same(next, store.measured) else { return }
      store.measured = next
      if !same(next, store.renderedMeasured), let ownerToken { invalidationStore._ownerObservationDidChange(ownerToken) }
    })
  }
  #endif
  #if !hasFeature(Embedded)
  wrapper.attributes["data-layout-type"] = pass.layoutType
  wrapper.attributes["data-layout-animatable"] = pass.layoutAnimatable
  #else
  wrapper.attributes["data-layout-type"] = "layout"
  #endif
  if let explicitLeading = pass.explicitLeading { wrapper._layoutAlignmentGuides[HorizontalAlignment.leading.cssValue] = { _ in explicitLeading } }
  if let explicitTrailing = pass.explicitTrailing { wrapper._layoutAlignmentGuides[HorizontalAlignment.trailing.cssValue] = { _ in explicitTrailing } }
  if let explicitTop = pass.explicitTop { wrapper._layoutAlignmentGuides[VerticalAlignment.top.cssValue] = { _ in explicitTop } }
  if let explicitBottom = pass.explicitBottom { wrapper._layoutAlignmentGuides[VerticalAlignment.bottom.cssValue] = { _ in explicitBottom } }
  wrapper._layoutExplicitHorizontalAlignment = pass.explicitHorizontal
  wrapper._layoutExplicitVerticalAlignment = pass.explicitVertical
  let layoutSpacing = pass.spacing
  if layoutSpacing._top != 0 || layoutSpacing._leading != 0 || layoutSpacing._bottom != 0 || layoutSpacing._trailing != 0 {
    wrapper.attributes["data-layout-spacing"] = [layoutSpacing._top, layoutSpacing._leading, layoutSpacing._bottom, layoutSpacing._trailing].map(_layoutNumber).joined(separator: ",")
  }
  let gridConfiguration = pass.grid
  let gridColumnWidths: [Double]? = gridConfiguration.flatMap { grid in
    guard !childNodes.isEmpty && childNodes.allSatisfy({ $0.classes.contains("grid-row") }) else { return nil }
    return _gridColumnWidths(childNodes, grid.horizontalSpacing)
  }
  let gridColumnAlignments = gridColumnWidths == nil ? [] : _gridColumnAlignments(childNodes)
  wrapper.children = childNodes.enumerated().map { index, child in
    let copy = (subviews[index]._renderedNode ?? child).clone()
    // A split pane's metadata is written on the child the split view renders, but the copy may be the node a layout
    // measured (a split view nested in a pane): the copy takes the split attributes of the child.
    if pass.splitAxis != nil {
      for (name, value) in child.attributes where name.hasPrefix("data-split-") { copy.attributes[name] = value }
    }
    let placement = subviews[index]._placement
    var size = placement.map { _LayoutNodeMeasurer.measure(copy, proposal: $0.proposal) } ?? subviews[index]._size
    // Split panes are concrete slots, not intrinsic-size suggestions. A
    // child must occupy the exact extent assigned by `_SplitLayout` so its
    // nested content receives the same proposal and the divider tracks the
    // pane edge even when the root view has no explicit frame.
    if pass.splitAxis != nil, let placement {
      size = placement.proposal.replacingUnspecifiedDimensions(by: size)
    }
    // A Spacer's intrinsic measurement is its minimum length. Once a stack
    // has allocated its flexible share, the placement proposal is the
    // resolved size; measuring the spacer node again would otherwise
    // collapse it back to that intrinsic minimum in the rendered tree.
    if copy.classes.contains("flex-spacer"), let placement {
      size = placement.proposal.replacingUnspecifiedDimensions(by: size)
    }
    if child.classes.contains("grid-row"), let gridColumnWidths {
      let gap = gridConfiguration?.horizontalSpacing ?? 8
      size.width = gridColumnWidths.reduce(0, +) + Double(max(0, gridColumnWidths.count - 1)) * Double(gap)
    }
    let origin: CGPoint
    if let placement {
      origin = CGPoint(x: placement.point.x - size.width * CGFloat(placement.anchor.x), y: placement.point.y - size.height * CGFloat(placement.anchor.y))
    } else {
      origin = CGPoint(x: 0, y: 0)
    }
    // A split pane's slot lives on an item around the pane, as a Layout subview's placement does below: re-rendering
    // the pane alone (a GeometryReader in it) would discard a slot written on the pane, and the pane would cover the
    // whole split view. The host lays out the pane as a semantic root proposed the item's box.
    if pass.splitAxis != nil, placement != nil, copy.attributes["data-split-item-index"] != nil {
      let item = _RenderNode.element("div")
      item.classes = ["split-item"]
      item.key = copy.key
      for name in Array(copy.attributes.keys) where name.hasPrefix("data-split-") {
        item.attributes[name] = copy.attributes[name]
        copy.attributes[name] = nil
      }
      item.styles["position"] = "absolute"
      item.styles["box-sizing"] = "border-box"
      item.styles["display"] = "grid"
      item.styles["left"] = "\(_layoutNumber(origin.x))px"
      item.styles["top"] = "\(_layoutNumber(origin.y))px"
      item.styles["width"] = "\(_layoutNumber(size.width))px"
      item.styles["height"] = "\(_layoutNumber(size.height))px"
      item.children = [copy]
      return item
    }
    #if hasFeature(Embedded)
    // The page lays out each subview's content for the proposal it was placed with and pins its anchor point to
    // the placed point from its real size (see `_layoutItemPlacement`); the estimates here only hold until
    // it has done so. The placement lives on an item around the subview so that re-rendering the subview alone
    // (a GeometryReader, a nested owner) cannot discard it.
    if let placement, pass.splitAxis == nil, !copy.classes.contains("grid-row") {
      func axis(_ value: CGFloat?) -> String { value.flatMap { $0.isFinite ? _layoutNumber($0) : nil } ?? "" }
      let item = _RenderNode.element("div")
      item.classes = ["layout-item"]
      item.key = copy.key
      item.attributes["data-layout-child-proposal"] = axis(placement.proposal.width) + "," + axis(placement.proposal.height)
      // The other proposals the layout asked this subview's size at (`sizeThatFits`): the page measures it at each one too, as
      // it measures it at the proposal it was placed with, so the layout reads the subview's real size there (the first few).
      let asks = subviews[index]._askedProposals.prefix(4).map { axis($0.width) + "," + axis($0.height) }
      if !asks.isEmpty { item.attributes["data-layout-asks"] = asks.joined(separator: ";") }
      item.attributes["data-layout-anchor"] = [placement.point.x, placement.point.y].map(_layoutNumber).joined(separator: ",") + "," + [Double(placement.anchor.x), Double(placement.anchor.y)].map { String($0) }.joined(separator: ",")
      item.styles["position"] = "absolute"
      item.styles["box-sizing"] = "border-box"
      _layoutItemPlacement(item, point: placement.point, anchor: placement.anchor)
      item.styles["width"] = "\(_layoutNumber(size.width))px"
      item.styles["height"] = "\(_layoutNumber(size.height))px"
      item.children = [copy]
      return item
    }
    #endif
    copy.styles["position"] = "absolute"
    copy.styles["box-sizing"] = "border-box"
    copy.styles["left"] = "\(_layoutNumber(origin.x))px"
    copy.styles["top"] = "\(_layoutNumber(origin.y))px"
    copy.styles["width"] = "\(_layoutNumber(size.width))px"
    copy.styles["height"] = "\(_layoutNumber(size.height))px"
    if copy.classes.contains("grid-row"), let grid = gridConfiguration {
      _positionGridRowChildren(in: copy, rowSize: size, alignment: grid.alignment, horizontalSpacing: grid.horizontalSpacing, columnWidths: gridColumnWidths, columnAlignments: gridColumnAlignments)
    }
    return copy
  }
  return wrapper
}

/// Where a subview's item sits: its `point` is the item's top leading corner, moved back by the `anchor`'s share of the
/// item's own size, which only the page knows (`--layout-anchor-x/y`, applied as a `translate` by the page's CSS layout).
@MainActor func _layoutItemPlacement(_ item: _RenderNode, point: CGPoint, anchor: UnitPoint) {
  item.styles["left"] = "\(_layoutNumber(point.x))px"
  item.styles["top"] = "\(_layoutNumber(point.y))px"
  item.styles["--layout-anchor-x"] = "\(_layoutNumber(-anchor.x * 100))%"
  item.styles["--layout-anchor-y"] = "\(_layoutNumber(-anchor.y * 100))%"
}

/// `"width,height"` with an empty field for an unspecified axis.
private func _parseProposal(_ raw: String) -> ProposedViewSize {
  var fields: [String] = []
  var current = ""
  for character in raw {
    if character == "," { fields.append(current); current = "" } else { current.append(character) }
  }
  fields.append(current)
  func axis(_ index: Int) -> CGFloat? {
    guard index < fields.count, !fields[index].isEmpty, let value = Double(fields[index]), value.isFinite, value >= 0 else { return nil }
    return CGFloat(value)
  }
  return ProposedViewSize(width: axis(0), height: axis(1))
}

@MainActor private func _layoutAnimatableDescription<L: Layout>(_ layout: L) -> String {
  if let erased = layout as? AnyLayout { return erased._animatableDescription }
  return _swiftUIWebDescribe(layout.animatableData)
}

@MainActor private func _layoutCacheKey(context: _RenderContext) -> String {
  let path = context._fiberPath.description
  return path.isEmpty ? "<root-layout>" : path
}

@MainActor private func _layoutGridConfiguration<L: Layout>(_ layout: L) -> _GridLayoutConfiguration? {
  if let grid = layout as? GridLayout {
    return _GridLayoutConfiguration(
      alignment: grid.alignment,
      horizontalSpacing: grid.horizontalSpacing ?? 8,
      verticalSpacing: grid.verticalSpacing ?? 8
    )
  }
  if let erased = layout as? AnyLayout { return erased._gridConfiguration }
  return nil
}
