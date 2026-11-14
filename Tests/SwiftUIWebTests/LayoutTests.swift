import Testing
import Foundation
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

private struct FixedLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
    CGSize(width: proposal.width ?? 120, height: proposal.height ?? 40)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
    for (index, subview) in subviews.enumerated() {
      let badgeOffset = CGFloat(subview[BadgeKey.self])
      let guideOffset = subview.dimensions(in: .unspecified)[.leading]
      subview.place(at: CGPoint(x: CGFloat(index) * 20 + badgeOffset + guideOffset, y: 0), proposal: ProposedViewSize(width: 20, height: 20))
    }
  }
}

private enum BadgeKey: LayoutValueKey {
  static let defaultValue = 0
}

private enum ThirdAlignment: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> CGFloat { context.width / 3 }
}

private final class LayoutProbe: @unchecked Sendable {
  var makeCount = 0
  var updateCount = 0
  var proposals: [ProposedViewSize] = []
}

private struct CachingLayout: Layout {
  let probe: LayoutProbe
  typealias Cache = Int

  func makeCache(subviews: LayoutSubviews) -> Int {
    probe.makeCount += 1
    return subviews.count
  }

  func updateCache(_ cache: inout Int, subviews: LayoutSubviews) {
    probe.updateCount += 1
    cache = subviews.count
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Int) -> CGSize {
    probe.proposals.append(proposal)
    return CGSize(width: proposal.width ?? 80, height: proposal.height ?? 24)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Int) {
    for subview in subviews {
      subview.place(at: CGPoint(x: bounds.origin.x, y: bounds.origin.y), proposal: ProposedViewSize(width: 20, height: 20))
    }
  }
}

private struct CustomGuideLayout: Layout {
  let guide: HorizontalAlignment
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
    CGSize(width: proposal.width ?? 80, height: proposal.height ?? 24)
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
    for subview in subviews {
      let value = subview.dimensions(in: .unspecified)[guide]
      subview.place(at: CGPoint(x: value, y: bounds.origin.y), proposal: ProposedViewSize(width: 20, height: 20))
    }
  }
}

@Suite
@MainActor
final class LayoutTests {
  @Test
  func testCustomLayoutMeasuresAndPlacesChildren() {
    let html = StaticHTMLFiberRenderer().render(
      FixedLayout {
        Text("A").layoutValue(key: BadgeKey.self, value: 7)
        Text("B")
      }
    )

    _expectTrue(html.contains("layout-box"))
    _expectTrue(html.contains("width: 120px;"))
    _expectTrue(html.contains("height: 40px;"))
    _expectTrue(html.contains("left: 7px;"))
    _expectTrue(html.contains("left: 20px;"))
    _expectTrue(html.contains("top: 0px;"))
  }

  @Test
  func testBuiltInLayoutTypesUseActualPlacement() {
    let html = StaticHTMLFiberRenderer().render(
      HStackLayout(spacing: 10) {
        Text("One")
        Text("Two")
      }
    )
    _expectTrue(html.contains("layout-box"))
    _expectTrue(html.contains("left: 0px;"))
    _expectTrue(html.components(separatedBy: "position: absolute;").count >= 3)
  }

  @Test
  func testSplitViewsUseSharedLayoutAndAccessibleDividers() {
    let html = StaticHTMLFiberRenderer().render(
      HSplitView {
        Text("Navigator").frame(minWidth: 120, idealWidth: 220, maxWidth: 420)
        VSplitView {
          Text("Editor")
          Text("Inspector")
        }
      }
      .frame(width: 900, height: 500)
    )
    _expectTrue(html.contains("split-pane"))
    _expectTrue(html.contains("data-split-axis=\"horizontal\""))
    _expectTrue(html.contains("data-split-axis=\"vertical\""))
    _expectTrue(html.contains("role=\"separator\""))
    _expectTrue(html.contains("aria-orientation=\"vertical\""))
    _expectTrue(html.contains("aria-orientation=\"horizontal\""))
    _expectTrue(html.contains("tabindex=\"0\""))
    _expectTrue(html.contains("touch-action: none;"))
    _expectTrue(html.contains("cursor: col-resize;"))
    _expectTrue(html.contains("min-width: 120px;"))
    _expectTrue(html.contains("max-width: 420px;"))
    // The pane receives a concrete slot from the split layout rather than
    // collapsing to the text's intrinsic width.
    _expectTrue(html.contains("width: 420px;"))
  }

  @Test
  func testSplitDividerPositionsPersistAcrossResponsiveUpdates() {
    let tree = FiberTree(
      HSplitView {
        Text("Master").id("master")
        Text("Detail").id("detail")
      }
      .frame(width: 640, height: 300)
    )
    let root = tree.root.renderNode
    _expectTrue(root.classes.contains("split-pane"))
    guard let key = root.attributes["data-split-key"] else {
      return _fail("split key missing")
    }
    tree._setSplitViewPositions(key: key, positions: [0.35, 0.65])
    _ = tree.update(
      HSplitView {
        Text("Master").id("master")
        Text("Detail").id("detail")
      }
      .frame(width: 1024, height: 400)
    )
    _expectEqual(tree.root.renderNode.attributes["data-split-positions"], "0.35,0.65")
    tree._setRootLayoutProposal(ProposedViewSize(width: 1280, height: 720))
    _ = tree.update(
      HSplitView {
        Text("Master").id("master")
        Text("Detail").id("detail")
      }
    )
    _expectEqual(tree.root.renderNode.attributes["data-split-positions"], "0.35,0.65")
    let items = tree.root.renderNode.children.filter { $0.attributes["data-split-item-index"] != nil }
    _expectEqual(items.map { $0.key }, [_FiberKey("master"), _FiberKey("detail")])
  }

  @Test
  func testSplitViewDividerReportedPositionsAreKeptForTheNextRender() {
    func split(width: CGFloat) -> some View {
      HSplitView {
        Text("Master").id("master")
        Text("Detail").id("detail")
      }
      .frame(width: width, height: 300)
    }
    let tree = FiberTree(split(width: 640))
    guard let key = tree.root.renderNode.attributes["data-split-key"] else {
      return _fail("split key missing")
    }
    func divider(in node: _RenderNode) -> _RenderNode? {
      if node.attributes["data-split-divider-index"] != nil { return node }
      return node.children.lazy.compactMap { divider(in: $0) }.first
    }
    guard let handle = divider(in: tree.root.renderNode) else {
      return _fail("divider missing")
    }
    handle.events["split-positions"]?.valueAction?("0.3,0.7")
    _expectEqual(tree._splitViewPositions(key: key), [0.3, 0.7])
    // A report that does not match the panes, or is not finite, is ignored.
    handle.events["split-positions"]?.valueAction?("0.5,0.2,0.3")
    handle.events["split-positions"]?.valueAction?("nan,1")
    _expectEqual(tree._splitViewPositions(key: key), [0.3, 0.7])
    _ = tree.update(split(width: 900))
    _expectEqual(tree.root.renderNode.attributes["data-split-positions"], "0.3,0.7")
  }

  @Test
  func testSplitViewNestedPaneKeepsItsSlot() {
    let tree = FiberTree(
      HSplitView {
        Text("Navigator").frame(idealWidth: 120)
        VSplitView {
          Text("Editor")
          Text("Inspector")
        }
      }
      .frame(width: 500, height: 200)
    )
    // Every item, including the items inside an item: the outer second pane is the nested split.
    func splitItems(in node: _RenderNode) -> [_RenderNode] {
      let own = node.attributes["data-split-item-index"] != nil ? [node] : []
      return own + node.children.flatMap { splitItems(in: $0) }
    }
    // The outer second pane (the nested split) and the nested split's second pane are both items.
    let second = splitItems(in: tree.renderNode).filter { $0.attributes["data-split-item-index"] == "1" }
    _expectEqual(second.count, 2)
  }

  @Test
  func testSplitViewPanesCarryTheirLimitsForTheBrowserHost() {
    let tree = FiberTree(
      HSplitView {
        Text("Capped").frame(minWidth: 80, idealWidth: 400, maxWidth: 100)
        Text("Flexible").frame(idealWidth: 100)
      }
      .frame(width: 500, height: 100)
    )
    func splitItems(in node: _RenderNode) -> [_RenderNode] {
      if node.attributes["data-split-item-index"] != nil { return [node] }
      return node.children.flatMap { splitItems(in: $0) }
    }
    let items = splitItems(in: tree.renderNode)
    _expectEqual(items.count, 2)
    _expectEqual(items.first?.attributes["data-split-min"], "80")
    _expectEqual(items.first?.attributes["data-split-max"], "100")
    _expectEqual(items.last?.attributes["data-split-min"], "0")
    _expectEqual(items.last?.attributes["data-split-max"], nil)
  }

  @Test
  func splitLayoutRedistributesAroundPaneLimitsAndPreservesUnsatisfiableMinimums() {
    func splitItems(in node: _RenderNode) -> [_RenderNode] {
      if node.attributes["data-split-item-index"] != nil { return [node] }
      return node.children.flatMap { splitItems(in: $0) }
    }

    let capped = FiberTree(
      HSplitView {
        Text("Capped").frame(idealWidth: 400, maxWidth: 100)
        Text("Flexible").frame(idealWidth: 100)
      }
      .frame(width: 500, height: 100)
    )
    let cappedItems = splitItems(in: capped.renderNode)
    #expect(cappedItems.count == 2)
    #expect(cappedItems.map { $0.styles["width"] } == ["100px", "394px"])

    let minimumsExceedAvailableSpace = FiberTree(
      HSplitView {
        Text("First minimum").frame(minWidth: 200, idealWidth: 240)
        Text("Second minimum").frame(minWidth: 200, idealWidth: 240)
      }
      .frame(width: 300, height: 100)
    )
    let constrainedItems = splitItems(in: minimumsExceedAvailableSpace.renderNode)
    #expect(constrainedItems.count == 2)
    #expect(constrainedItems.map { $0.styles["width"] } == ["200px", "200px"])
  }

  @Test
  func testSplitViewPreservesStatefulChildrenWhenReconciled() {
    struct StatefulChild: View {
      @State var taps = 0
      var body: some View { Button("taps-\(taps)") { taps += 1 } }
    }
    struct Screen: View {
      let title: String
      var body: some View {
        HSplitView { StatefulChild().id("stateful"); Text(title) }
      }
    }
    let tree = FiberTree(Screen(title: "peer"))
    tree.dispatch(event: "click")
    _expectTrue(tree.renderNode.htmlDescription.contains("taps-1"))
    _ = tree.update(Screen(title: "updated"))
    _expectTrue(tree.renderNode.htmlDescription.contains("taps-1"))
  }

  @Test
  func testGridLayoutHonorsGridRowChildren() {
    let html = StaticHTMLFiberRenderer().render(
      GridLayout(horizontalSpacing: 6, verticalSpacing: 12) {
        GridRow { Text("A"); Text("B") }
        GridRow { Text("C"); Text("D") }
      }
    )
    _expectTrue(html.contains("layout-box"))
    _expectTrue(html.contains("grid-row"))
    _expectTrue(html.contains("top: 32px;"))
  }

  @Test
  func testFrameForwardsAProposalIntoTheLayoutBoundary() {
    let html = StaticHTMLFiberRenderer().render(
      FixedLayout { Text("content") }
        .frame(width: 200, height: 90)
    )
    _expectTrue(html.contains("width: 200px;"))
    _expectTrue(html.contains("height: 90px;"))
  }

  @Test
  func testAlignmentGuideIsAvailableDuringPlacement() {
    let html = StaticHTMLFiberRenderer().render(
      FixedLayout {
        Text("A").alignmentGuide(.leading) { _ in 13 }
      }
    )
    _expectTrue(html.contains("left: 13px;"))
  }

  @Test
  func testExplicitAlignmentFromNestedLayoutFlowsThroughDimensions() {
    struct ExplicitLayout: Layout {
      func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        CGSize(width: 48, height: 20)
      }
      func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGFloat? {
        guide == .leading ? 9 : nil
      }
      func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {}
    }

    let html = StaticHTMLFiberRenderer().render(
      CustomGuideLayout(guide: .leading) {
        ExplicitLayout { Text("nested") }
      }
    )
    _expectTrue(html.contains("left: 9px;"))
  }

  @Test
  func testExplicitCustomAlignmentFromNestedLayoutFlowsThroughDimensions() {
    let custom = HorizontalAlignment(ThirdAlignment.self)
    struct ExplicitCustomLayout: Layout {
      let guide: HorizontalAlignment
      func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        CGSize(width: 48, height: 20)
      }
      func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGFloat? {
        guide == self.guide ? 7 : nil
      }
      func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {}
    }

    let html = StaticHTMLFiberRenderer().render(
      CustomGuideLayout(guide: custom) {
        ExplicitCustomLayout(guide: custom) { Text("nested-custom") }
      }
    )
    _expectTrue(html.contains("left: 7px;"))
  }

  @Test
  func testCustomAlignmentIDAndLayoutPriorityAreSemantic() {
    let custom = HorizontalAlignment(ThirdAlignment.self)
    let html = StaticHTMLFiberRenderer().render(
      HStackLayout(spacing: 4) {
        Text("low").layoutPriority(1).alignmentGuide(custom) { _ in 11 }
        Text("high").layoutPriority(3)
      }
      .frame(width: 120, height: 24)
    )
    _expectTrue(html.contains("data-layout-priority=\"1\""))
    _expectTrue(html.contains("data-layout-priority=\"3\""))

    let alignmentHTML = StaticHTMLFiberRenderer().render(
      CustomGuideLayout(guide: custom) {
        Text("guide").alignmentGuide(custom) { _ in 17 }
      }
    )
    _expectTrue(alignmentHTML.contains("left: 17px;"))
  }

  @Test
  func testLayoutCacheSurvivesFiberUpdatesAndReceivesProposals() {
    let probe = LayoutProbe()
    let tree = FiberTree(
      CachingLayout(probe: probe) { Text("cached") }
        .frame(width: 160, height: 48)
    )
    _expectEqual(probe.makeCount, 1)
    _expectTrue(probe.proposals.contains { $0.width == 160 && $0.height == 48 })

    _ = tree.update(
      CachingLayout(probe: probe) { Text("updated") }
        .frame(width: 180, height: 52)
    )
    _expectEqual(probe.makeCount, 1)
    _expectGreaterThanOrEqual(probe.updateCount, 2)
    _expectTrue(probe.proposals.contains { $0.width == 180 && $0.height == 52 })
  }

  @Test
  func testRootLayoutRecomputesWhenRendererViewportProposalChanges() {
    let probe = LayoutProbe()
    let tree = FiberTree(CachingLayout(probe: probe) { Text("viewport") })

    tree._setRootLayoutProposal(ProposedViewSize(width: 320, height: 180))
    _ = tree.update(CachingLayout(probe: probe) { Text("viewport-320") })
    _expectTrue(probe.proposals.contains { $0.width == 320 && $0.height == 180 })

    tree._setRootLayoutProposal(ProposedViewSize(width: 640, height: 240))
    _ = tree.update(CachingLayout(probe: probe) { Text("viewport-640") })
    _expectTrue(probe.proposals.contains { $0.width == 640 && $0.height == 240 })
  }

  @Test
  func testNestedLayoutReceivesChildProposalInsteadOfBrowserMeasurement() {
    let probe = LayoutProbe()
    let html = StaticHTMLFiberRenderer().render(
      FixedLayout {
        CachingLayout(probe: probe) { Text("nested") }
      }
      .frame(width: 200, height: 60)
    )
    _expectTrue(html.contains("width: 200px;"))
    _expectTrue(probe.proposals.contains { $0.width == 20 && $0.height == 20 })
  }

  @Test
  func testLayoutProtocolHasAnimatableDefaultAndCustomImplementationsCompile() {
    struct AnimatedLayout: Layout {
      var amount: CGFloat
      var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
      }
      func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? amount, height: proposal.height ?? 10)
      }
      func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        for subview in subviews {
          subview.place(at: bounds.origin, proposal: ProposedViewSize(width: amount, height: 10))
        }
      }
    }

    let html = StaticHTMLFiberRenderer().render(
      AnimatedLayout(amount: 36) { Text("animated") }
        .animation(.easeInOut(duration: 0.2), value: 36)
    )
    _expectTrue(html.contains("layout-box"))
    // The timing is metadata the page applies when the value changes, not a permanent transition.
    _expectTrue(html.contains("data-animation-timing=\"200ms ease-in-out\""))
    _expectTrue(!html.contains("transition:"))
    _expectTrue(html.contains("data-layout-animation=\"true\""))
  }

  @Test
  func testAnyLayoutSwitchKeepsTheLayoutContainerAndChildFibers() {
    struct Switcher: View {
      let vertical: Bool
      var selectedLayout: AnyLayout { vertical ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout()) }
      var body: some View {
        selectedLayout {
          Text("first")
          Text("second")
        }
      }
    }

    let tree = FiberTree(Switcher(vertical: false))
    let rootID = ObjectIdentifier(tree.root)
    let childIDs = tree.root.children.map(ObjectIdentifier.init)
    _ = tree.update(Switcher(vertical: true))
    _expectEqual(rootID, ObjectIdentifier(tree.root))
    _expectEqual(childIDs, tree.root.children.map(ObjectIdentifier.init))
    _expectTrue(tree.renderNode.htmlDescription.contains("layout-box"))
  }

  @Test
  func testAnyLayoutSwitchPreservesKeyedChildState() {
    struct StatefulChild: View {
      @State var taps = 0
      var body: some View {
        Button("taps-\(taps)") { taps += 1 }
      }
    }
    struct Switcher: View {
      let vertical: Bool
      var body: some View {
        let selected: AnyLayout = vertical ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout())
        selected {
          StatefulChild().id("stable-child")
          Text("peer")
        }
      }
    }

    let tree = FiberTree(Switcher(vertical: false))
    tree.dispatch(event: "click")
    _expectTrue(tree.renderNode.htmlDescription.contains("taps-1"))
    _ = tree.update(Switcher(vertical: true))
    _expectTrue(tree.renderNode.htmlDescription.contains("taps-1"))
  }

  @Test
  func testAnyLayoutUsesTheNewestValueTypeLayoutWithRetainedCache() {
    struct Spaced: View {
      let spacing: CGFloat
      var body: some View {
        AnyLayout(HStackLayout(spacing: spacing)) {
          Text("one")
          Text("two")
        }
      }
    }

    let tree = FiberTree(Spaced(spacing: 2))
    let initial = tree.renderNode.htmlDescription
    _ = tree.update(Spaced(spacing: 20))
    let updated = tree.renderNode.htmlDescription
    _expectNotEqual(initial, updated)
    _expectTrue(updated.contains("left: 44.96px;") || updated.contains("left: 44.9px;"))
  }

  @Test
  func testListDefersLargeForEachButKeepsSmallCollectionsEager() {
    struct Item: Identifiable { let id: Int }
    let items = (0..<100).map(Item.init)
    let largeTree = FiberTree(List(items) { item in Text("row-\(item.id)") })
    _expectEqual(largeTree._lazyCollections().count, 1)
    _expectFalse(largeTree.renderNode.htmlDescription.contains("row-99"))

    let smallItems = (0..<3).map(Item.init)
    let smallHTML = StaticHTMLFiberRenderer().render(List(smallItems) { item in Text("small-\(item.id)") })
    _expectTrue(smallHTML.contains("small-2"))
  }

  @Test
  func testTableUsesTypedColumnCellsAndADeferredBody() {
    struct Row: Identifiable { let id: Int; let name: String }
    let rows = (0..<100).map { Row(id: $0, name: "name-\($0)") }
    let table = Table(rows) {
      TableColumn("Name", value: \Row.name)
    }
    let tree = FiberTree(table)
    let infos = tree._lazyCollections()
    _expectEqual(infos.count, 1)
    _expectTrue(tree.renderNode.htmlDescription.contains("Name"))
    _expectFalse(tree.renderNode.htmlDescription.contains("name-99"))

    if let info = infos.first {
      _ = tree._materializeLazyCollection(
        ownerIdentity: info.ownerIdentity,
        indices: [0, 1],
        beforeExtent: 0,
        afterExtent: 3_920
      )
      _expectTrue(tree.renderNode.htmlDescription.contains("name-1"))
    }

    let eagerHTML = StaticHTMLFiberRenderer().render(table)
    _expectTrue(eagerHTML.contains("name-99"))
  }

  @Test
  func testListMaterializationRetainsKeyedRowsAndOnlyMountsRequestedRange() {
    struct Item: Identifiable { let id: Int }
    let items = (0..<100).map(Item.init)
    let tree = FiberTree(List {
      ForEach(items) { item in Text("item-\(item.id)") }
    })
    guard let info = tree._lazyCollections().first else {
      return _fail("expected a deferred list descriptor")
    }
    let mutations = tree._materializeLazyCollection(
      ownerIdentity: info.ownerIdentity,
      indices: Array(10..<20),
      beforeExtent: 640,
      afterExtent: 5_120
    )
    _expectFalse(mutations.isEmpty)
    let html = tree.renderNode.htmlDescription
    _expectTrue(html.contains("item-10"))
    _expectTrue(html.contains("item-19"))
    _expectFalse(html.contains("item-0"))
    _expectFalse(html.contains("item-99"))
  }

  @Test
  func testAspectRatioOnAForEachAppliesToEachElement() {
    func count(_ node: _RenderNode, class name: String) -> Int {
      (node.classes.contains(name) ? 1 : 0) + node.children.reduce(0) { $0 + count($1, class: name) }
    }
    let view = Group { ForEach(0..<3, id: \.self) { _ in Color.red } }.aspectRatio(1, contentMode: .fit)
    _expectEqual(count(FiberTree(view).renderNode, class: "aspect-box"), 3)
  }

  @Test
  func testBackgroundOnAGroupDecoratesEachElement() {
    func count(_ node: _RenderNode, class name: String) -> Int {
      (node.classes.contains(name) ? 1 : 0) + node.children.reduce(0) { $0 + count($1, class: name) }
    }
    let shaped = Group { Text("a"); Text("b"); Text("c") }.background(Color.red, in: Capsule())
    _expectEqual(count(FiberTree(shaped).renderNode, class: "backdrop-layer"), 3)
    let padded = Group { Text("a"); Text("b"); Text("c") }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
      .background(Color.red, in: RoundedRectangle(cornerRadius: 4))
    _expectEqual(count(FiberTree(padded).renderNode, class: "backdrop-layer"), 3)
  }

  @Test
  func testALayoutItemIsPlacedAtItsPointAndAnchoredByItsOwnSize() {
    // The page decides the size, so the item only states the point and the anchor as shares of its own size.
    let item = _RenderNode.element("div")
    _layoutItemPlacement(item, point: CGPoint(x: 40.5, y: 12), anchor: .center)
    _expectEqual(item.styles["left"], "40.5px")
    _expectEqual(item.styles["top"], "12px")
    _expectEqual(item.styles["--layout-anchor-x"], "-50%")
    _expectEqual(item.styles["--layout-anchor-y"], "-50%")
    _layoutItemPlacement(item, point: CGPoint(x: 0, y: 0), anchor: .topLeading)
    _expectEqual(item.styles["--layout-anchor-x"], "0%")
    _layoutItemPlacement(item, point: CGPoint(x: 0, y: 0), anchor: .bottomTrailing)
    _expectEqual(item.styles["--layout-anchor-y"], "-100%")
  }
}
