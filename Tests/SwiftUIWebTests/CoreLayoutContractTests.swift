import Foundation
import Testing
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

private struct SpacingContractLayout: Layout {
  func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing {
    subviews.reduce(.zero) { $0.union($1.spacing) }
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let gaps = subviews.indices.dropLast().map { index in
      subviews[index].spacing.distance(to: subviews[index + 1].spacing, along: .horizontal)
    }
    return CGSize(width: sizes.reduce(0) { $0 + $1.width } + gaps.reduce(0, +),
                  height: sizes.map(\.height).max() ?? 0)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.origin.x
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      subviews[index].place(at: CGPoint(x: x, y: bounds.origin.y),
                            proposal: ProposedViewSize(width: size.width, height: size.height))
      x += size.width
      if index + 1 < subviews.count {
        x += subviews[index].spacing.distance(to: subviews[index + 1].spacing, along: .horizontal)
      }
    }
  }
}

private func findLayoutNode(_ node: _RenderNode, typeName: String) -> _RenderNode? {
  if node.attributes["data-layout-type"] == typeName { return node }
  for child in node.children {
    if let match = findLayoutNode(child, typeName: typeName) { return match }
  }
  return nil
}

private enum ContractHorizontalGuide: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> CGFloat { context.width / 2 }
}

private enum ContractVerticalGuide: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> CGFloat { context.height / 2 }
}

private final class IntrinsicLayoutProbe: @unchecked Sendable {
  var measuredSizes: [CGSize] = []
  var collectionIsEqualToItself = false
  var elementsAreEqualToThemselves = false
}

private enum LayoutValueContractKey: LayoutValueKey {
  static let defaultValue = 0
}

private final class LayoutValueContractProbe: @unchecked Sendable {
  var values: [Int] = []
}

private struct LayoutValueReadingLayout: Layout {
  let probe: LayoutValueContractProbe

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    probe.values = subviews.map { $0[LayoutValueContractKey.self] }
    return CGSize(width: probe.values.reduce(0) { $0 + $1 }, height: 20)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      subview.place(at: bounds.origin, proposal: .unspecified)
    }
  }
}

private struct IntrinsicMeasuringLayout: Layout {
  let probe: IntrinsicLayoutProbe

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    probe.collectionIsEqualToItself = subviews == subviews
    probe.elementsAreEqualToThemselves = subviews.allSatisfy { $0 == $0 }
    probe.measuredSizes = subviews.map { $0.sizeThatFits(.unspecified) }
    return CGSize(
      width: probe.measuredSizes.map(\.width).max() ?? 0,
      height: probe.measuredSizes.map(\.height).max() ?? 0
    )
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      subview.place(at: bounds.origin, proposal: .unspecified)
    }
  }
}

private struct ExplicitAlignmentLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    CGSize(width: 40, height: 20)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      subview.place(at: bounds.origin, proposal: ProposedViewSize(width: 40, height: 20))
    }
  }

  func explicitAlignment(
    of guide: VerticalAlignment,
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGFloat? {
    guide == VerticalAlignment(ContractVerticalGuide.self) ? 7 : nil
  }
}

@Suite
@MainActor
struct CoreLayoutContractTests {
  @Test
  func proposedSizesDimensionsAndAnimatableValuesKeepTheirValueContracts() {
    #expect(ProposedViewSize.zero == ProposedViewSize(width: 0, height: 0))
    #expect(ProposedViewSize.unspecified.replacingUnspecifiedDimensions() == CGSize(width: 10, height: 10))
    #expect(ProposedViewSize(width: 40, height: nil).replacingUnspecifiedDimensions(
      by: CGSize(width: 80, height: 24)
    ) == CGSize(width: 40, height: 24))
    #expect(ProposedViewSize(CGSize(width: 12, height: 18)) == ProposedViewSize(width: 12, height: 18))
    #expect(ProposedViewSize.infinity.width == .infinity)

    let dimensions = ViewDimensions(size: CGSize(width: 90, height: 30))
    #expect(dimensions.width == 90)
    #expect(dimensions.height == 30)
    #expect(dimensions[HorizontalAlignment.leading] == 0)
    #expect(dimensions[HorizontalAlignment.center] == 45)
    #expect(dimensions[HorizontalAlignment.trailing] == 90)
    #expect(dimensions[VerticalAlignment.top] == 0)
    #expect(dimensions[VerticalAlignment.center] == 15)
    #expect(dimensions[VerticalAlignment.bottom] == 30)

    let empty = EmptyAnimatableData()
    #expect(empty + .zero == .zero)
    #expect(empty - .zero == .zero)
    #expect(empty.magnitudeSquared == 0)
    var emptyScaled = EmptyAnimatableData.zero
    emptyScaled.scale(by: -12)
    #expect(emptyScaled == .zero)

    let pairZero = AnimatablePair<Double, CGFloat>.zero
    #expect(pairZero.first == 0 && pairZero.second == 0)
    #expect(pairZero.magnitudeSquared == 0)

    var pair = AnimatablePair<Double, CGFloat>(2, 3)
    #expect(pair.magnitudeSquared == 13)
    pair.scale(by: 2)
    #expect(pair.first == 4)
    #expect(pair.second == 6)
    let sum = pair + AnimatablePair<Double, CGFloat>(1, 2)
    let difference = sum - AnimatablePair<Double, CGFloat>(3, 4)
    #expect(sum.first == 5 && sum.second == 8)
    #expect(difference.first == 2 && difference.second == 4)

    var scalar: Double = 3
    scalar.scale(by: -2)
    #expect(scalar == -6)
    var platformScalar: CGFloat = 2
    platformScalar.scale(by: 2.5)
    #expect(platformScalar == 5)

    #expect(LayoutProperties().stackOrientation == nil)
    #expect(HStackLayout.layoutProperties.stackOrientation == .horizontal)
    #expect(VStackLayout.layoutProperties.stackOrientation == .vertical)
    #expect(AnyLayout.layoutProperties.stackOrientation == nil)
    #expect(IntrinsicMeasuringLayout.layoutProperties.stackOrientation == nil)
    #expect(IntrinsicMeasuringLayout(probe: IntrinsicLayoutProbe())._swiftUIWebSplitDividerThickness == 0)
    #expect(type(of: AnyLayout.Cache()) == AnyLayout.Cache.self)
    #expect(ZStackLayout(alignment: .topLeading)._swiftUIWebSemanticLayout?["data-layout-kind"] == "zstack")

    var nonAnimatableLayout = VStackLayout()
    let defaultAnimationData = nonAnimatableLayout.animatableData
    nonAnimatableLayout.animatableData = .zero
    #expect(defaultAnimationData == .zero)
    #expect(nonAnimatableLayout.animatableData == .zero)
  }

  @Test
  func rendererLayoutStoresRejectMismatchedEntriesAndClampSplitFractions() {
    let cache = _LayoutCacheStore()
    #expect(cache.value(for: "screen", identifier: "hstack") == nil)
    cache.setValue(12, for: "screen", identifier: "hstack")
    #expect(cache.value(for: "screen", identifier: "hstack") as? Int == 12)
    #expect(cache.value(for: "screen", identifier: "vstack") == nil)
    cache.setValue("updated", for: "screen", identifier: "hstack")
    #expect(cache.value(for: "screen", identifier: "hstack") as? String == "updated")

    for index in 0..<2_048 {
      cache.setValue(index, for: "entry-\(index)", identifier: "layout")
    }
    cache.setValue(2_048, for: "entry-overflow", identifier: "layout")
    #expect(cache.value(for: "entry-overflow", identifier: "layout") as? Int == 2_048)
    cache.removeAll()
    #expect(cache.value(for: "screen", identifier: "hstack") == nil)

    let split = _SplitViewStateStore()
    #expect(split.value(for: "settings") == nil)
    split.setValue([-0.25, 0.4, 1.25], for: "settings")
    #expect(split.value(for: "settings") == [0, 0.4, 1])
    split.setValue([0.7], for: "settings")
    #expect(split.value(for: "settings") == [0.7])
    split.removeValue(for: "settings")
    #expect(split.value(for: "settings") == nil)
  }

  @Test
  func builtinStacksDistributeFlexibleSpaceAndKeepAlignmentSemantics() {
    let horizontal = StaticHTMLFiberRenderer().render(
      HStackLayout(alignment: .bottom, spacing: 0) {
        Text("left").frame(width: 20, height: 10)
        Spacer()
        Text("right").frame(width: 30, height: 15)
      }
      .frame(width: 100, height: 30)
    )
    #expect(horizontal.contains("data-layout-type=\"SwiftUIWebCore.HStackLayout\""))
    #expect(horizontal.contains("data-layout-content-width=\"100\""))
    #expect(horizontal.contains("width: 50px;"))
    #expect(horizontal.contains("left: 70px;"))

    let vertical = StaticHTMLFiberRenderer().render(
      VStackLayout(alignment: .trailing, spacing: 0) {
        Text("top").frame(width: 20, height: 10)
        Spacer()
        Text("bottom").frame(width: 30, height: 15)
      }
      .frame(width: 60, height: 100)
    )
    #expect(vertical.contains("data-layout-type=\"SwiftUIWebCore.VStackLayout\""))
    #expect(vertical.contains("data-layout-content-height=\"100\""))
    #expect(vertical.contains("top: 85px;"))
    #expect(vertical.contains("left: 30px;"))

    let overlay = StaticHTMLFiberRenderer().render(
      ZStackLayout(alignment: .bottomTrailing) {
        Text("short").frame(width: 30, height: 12)
        Text("wide").frame(width: 60, height: 24)
      }
      .frame(width: 120, height: 80)
    )
    #expect(overlay.contains("data-layout-type=\"SwiftUIWebCore.ZStackLayout\""))
    #expect(overlay.contains("left: 60px;"))
    #expect(overlay.contains("top: 56px;"))

    let baselines = StaticHTMLFiberRenderer().render(
      HStackLayout(alignment: .firstTextBaseline, spacing: 0) {
        Text("Tall").alignmentGuide(.firstTextBaseline) { $0.height * 0.8 }
        Text("Short").alignmentGuide(.firstTextBaseline) { $0.height * 0.4 }
      }
    )
    #expect(baselines.contains("data-layout-type=\"SwiftUIWebCore.HStackLayout\""))
    #expect(baselines.components(separatedBy: "top: ").count >= 3)
  }

  @Test
  func stacksCompressLowerPriorityChildrenBeforeHigherPriorityChildren() {
    let horizontalTree = FiberTree(
      HStackLayout(spacing: 0) {
        Text("lower").frame(width: 80).layoutPriority(0)
        Text("higher").frame(width: 80).layoutPriority(1)
      }
      .frame(width: 100, height: 24)
    )
    guard let horizontal = findLayoutNode(
      horizontalTree.renderNode,
      typeName: "SwiftUIWebCore.HStackLayout"
    ), horizontal.children.count == 2 else {
      Issue.record("Expected the horizontal stack to render both measured children")
      return
    }
    #expect(horizontal.children[0].styles["width"] == "20px")
    #expect(horizontal.children[1].styles["width"] == "80px")
    #expect(horizontal.children[0].attributes["data-layout-priority"] == "0")
    #expect(horizontal.children[1].attributes["data-layout-priority"] == "1")

    let verticalTree = FiberTree(
      VStackLayout(spacing: 0) {
        Text("lower").frame(height: 60).layoutPriority(0)
        Text("higher").frame(height: 40).layoutPriority(1)
      }
      .frame(width: 80, height: 60)
    )
    guard let vertical = findLayoutNode(
      verticalTree.renderNode,
      typeName: "SwiftUIWebCore.VStackLayout"
    ), vertical.children.count == 2 else {
      Issue.record("Expected the vertical stack to render both measured children")
      return
    }
    #expect(vertical.children[0].styles["height"] == "20px")
    #expect(vertical.children[1].styles["height"] == "40px")
    #expect(vertical.children[0].attributes["data-layout-priority"] == "0")
    #expect(vertical.children[1].attributes["data-layout-priority"] == "1")
  }

  @Test
  func builtInStacksAndOverlaysHonorCustomAlignmentGuides() {
    let horizontal = StaticHTMLFiberRenderer().render(
      HStackLayout(alignment: VerticalAlignment(ContractVerticalGuide.self), spacing: 0) {
        Text("first").alignmentGuide(VerticalAlignment(ContractVerticalGuide.self)) { _ in 11 }
        Text("second").alignmentGuide(VerticalAlignment(ContractVerticalGuide.self)) { _ in 5 }
      }
    )
    #expect(horizontal.contains("top: 6px;"))

    let vertical = StaticHTMLFiberRenderer().render(
      VStackLayout(alignment: HorizontalAlignment(ContractHorizontalGuide.self), spacing: 0) {
        Text("first").alignmentGuide(HorizontalAlignment(ContractHorizontalGuide.self)) { _ in 15 }
        Text("second").alignmentGuide(HorizontalAlignment(ContractHorizontalGuide.self)) { _ in 5 }
      }
    )
    #expect(vertical.contains("left: 10px;"))

    let horizontalGuide = HorizontalAlignment(ContractHorizontalGuide.self)
    let verticalGuide = VerticalAlignment(ContractVerticalGuide.self)
    let overlay = StaticHTMLFiberRenderer().render(
      ZStackLayout(alignment: Alignment(horizontal: horizontalGuide, vertical: verticalGuide)) {
        Text("first")
          .alignmentGuide(horizontalGuide) { _ in 10 }
          .alignmentGuide(verticalGuide) { _ in 5 }
        Text("second")
          .alignmentGuide(horizontalGuide) { _ in 20 }
          .alignmentGuide(verticalGuide) { _ in 12 }
      }
      .frame(width: 80, height: 40)
    )
    #expect(overlay.contains("left: 30px;"))
    #expect(overlay.contains("left: 20px;"))
    #expect(overlay.contains("top: 15px;"))
    #expect(overlay.contains("top: 8px;"))
  }

  @Test
  func customLayoutCombinesChildSpacingInsteadOfDroppingInsets() {
    let html = StaticHTMLFiberRenderer().render(
      SpacingContractLayout {
        Text("Leading").padding(.trailing, 3)
        Text("Trailing").padding(.leading, 5)
      }
    )
    #expect(html.contains("data-layout-spacing=\"4,9,4,7\""))
    #expect(html.contains("data-layout-content-width=\"148.8\""))
    #expect(html.contains("padding-inline-start: 5px;"))
    #expect(html.contains("padding-inline-end: 3px;"))
  }

  @Test
  func nestedCustomLayoutSpacingIsReadBackForItsParent() {
    let tree = FiberTree(
      SpacingContractLayout {
        SpacingContractLayout {
          Text("Nested").padding(4)
        }
        Text("Sibling").padding(2)
      }
    )

    var nodes: [_RenderNode] = []
    func collect(_ node: _RenderNode) {
      nodes.append(node)
      node.children.forEach(collect)
    }
    collect(tree.renderNode)
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("data-layout-spacing=\"8,8,8,8\""))
    #expect(tree.renderNode.attributes["data-layout-content-width"] != nil)
  }

  @Test
  func layoutValueModifierDeliversTypedValuesToCustomLayoutSubviews() {
    let probe = LayoutValueContractProbe()
    let tree = FiberTree(LayoutContainer(
      layout: LayoutValueReadingLayout(probe: probe),
      content: Text("Priority value").layoutValue(key: LayoutValueContractKey.self, value: 42)
    ))

    _ = tree.renderNode

    #expect(probe.values == [42])
  }

  @Test
  func customVerticalAlignmentQueriesUseTheCommittedLayoutSnapshot() throws {
    let tree = FiberTree(ExplicitAlignmentLayout { Text("Guided child") })
    let node = tree.renderNode
    let guide = VerticalAlignment(ContractVerticalGuide.self)
    let queriedValue = try #require(node._layoutExplicitVerticalAlignment?(guide))

    #expect(queriedValue == 7)
    #expect(node.htmlDescription.contains("Guided child"))
  }

  @Test
  func gridLayoutMeasuresOrdinaryChildrenAndExplicitGridRows() {
    let ordinary = StaticHTMLFiberRenderer().render(
      GridLayout(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 4) {
        Text("A")
        Text("B")
        Text("C")
      }
    )
    #expect(ordinary.contains("data-layout-type=\"SwiftUIWebCore.GridLayout\""))
    #expect(ordinary.contains("data-layout-content-width="))
    #expect(ordinary.contains("data-layout-content-height="))
    #expect(ordinary.contains("left: "))

    let rows = StaticHTMLFiberRenderer().render(
      GridLayout(horizontalSpacing: 10, verticalSpacing: 5) {
        GridRow { Text("Name"); Text("Value") }
        GridRow { Text("Longer name"); Text("42") }
      }
    )
    #expect(rows.contains("grid-row"))
    #expect(rows.contains("position: relative"))
    #expect(rows.contains("left: "))
    #expect(rows.contains("top: "))

    let mixedChildren = StaticHTMLFiberRenderer().render(
      GridLayout(horizontalSpacing: 8) {
        GridRow { Text("Cell"); Image(systemName: "star") }
        Text("A child outside an explicit row")
      }
    )
    #expect(mixedChildren.contains("grid-row"))
    #expect(mixedChildren.contains("data-symbol=\"star\""))
    #expect(mixedChildren.contains("position: absolute"))
  }

  @Test
  func layoutSubviewMeasurementsCoverIntrinsicImagesAndStackChildren() {
    let probe = IntrinsicLayoutProbe()
    let tree = FiberTree(
      IntrinsicMeasuringLayout(probe: probe) {
        Image(systemName: "gear")
        Image("/remote.png", alt: "Remote")
        HStack { Text("first").frame(width: 30, height: 10); Text("second").frame(width: 40, height: 14) }
        VStack { Text("top").frame(width: 42, height: 9); Text("bottom").frame(width: 28, height: 11) }
      }
    )

    #expect(probe.collectionIsEqualToItself)
    #expect(probe.elementsAreEqualToThemselves)
    #expect(probe.measuredSizes.count == 4)
    #expect(probe.measuredSizes[0] == CGSize(width: 16, height: 16))
    #expect(probe.measuredSizes[1] == CGSize(width: 32, height: 32))
    #expect(probe.measuredSizes[2].width >= 70)
    #expect(probe.measuredSizes[2].height >= 14)
    #expect(probe.measuredSizes[3].width >= 42)
    #expect(probe.measuredSizes[3].height >= 20)
    #expect(tree.renderNode.attributes["data-layout-content-width"] != nil)
  }

  @Test
  func erasedGridLayoutRetainsGridSemanticsAndColumnMeasurement() {
    let html = StaticHTMLFiberRenderer().render(
      AnyLayout(GridLayout(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6)) {
        GridRow { Text("Name"); Image(systemName: "person") }
        GridRow { Text("Longer name"); Button("Open") {} }
      }
    )

    #expect(html.contains("data-layout-type=\"SwiftUIWebCore.AnyLayout\""))
    #expect(html.contains("data-layout-content-width=\"136.8\""))
    #expect(html.contains("data-symbol=\"person\""))
    #expect(html.contains("grid-row"))
    #expect(html.contains("position: absolute"))
  }

  @Test
  func frameAlignmentRespectsTheLayoutKindOfItsContent() {
    let stack = FiberTree(
      VStack { Text("Stack content") }
        .frame(width: 240, height: 120, alignment: .bottomTrailing)
    ).renderNode
    #expect(stack.attributes["data-frame-alignment"] == "end")
    #expect(stack.styles["margin-left"] == "auto")
    #expect(stack.styles["margin-top"] == "auto")
    #expect(stack.styles["place-items"] == nil)

    let background = FiberTree(
      Text("Base")
        .background(alignment: .bottomTrailing) { Text("Backdrop") }
        .frame(width: 180, height: 72, alignment: .topLeading)
    ).renderNode
    #expect(background.classes.contains("frame-box"))
    #expect(background.styles["place-items"] == "start")

    let overlay = FiberTree(
      Text("Base")
        .overlay(alignment: .topLeading) { Text("Badge") }
        .frame(width: 180, height: 72, alignment: .bottomTrailing)
    ).renderNode
    #expect(overlay.classes.contains("frame-box"))
    #expect(overlay.styles["place-items"] == "end")

    let presentationHost = FiberTree(
      Text("Base")
        .sheet(isPresented: .constant(true)) { Text("Sheet content") }
        .frame(width: 180, height: 72, alignment: .topTrailing)
    ).renderNode
    #expect(presentationHost.children.first?.classes.contains("presentation-host") == true)
    #expect(presentationHost.styles["place-items"] == "start end")

    let zstack = FiberTree(
      ZStack { Text("Back"); Text("Front") }
        .frame(width: 180, height: 72, alignment: .topTrailing)
    ).renderNode
    #expect(zstack.styles["place-items"] == "start end")
  }

  @Test
  func fixedAndFlexibleFramesAlignCustomLayoutPlacements() {
    func layoutView() -> some View {
      SpacingContractLayout {
        Text("Leading").padding(.trailing, 3)
        Text("Trailing").padding(.leading, 5)
      }
    }

    func firstPlacedChild(in node: _RenderNode) -> _RenderNode? {
      if node.attributes["data-layout-content-width"] != nil {
        return node.children.first { $0.styles["position"] == "absolute" }
      }
      for child in node.children {
        if let placed = firstPlacedChild(in: child) { return placed }
      }
      return nil
    }

    let intrinsicTree = FiberTree(layoutView()).renderNode
    let intrinsicChild = firstPlacedChild(in: intrinsicTree)
    let intrinsicLeft = Double((intrinsicChild?.styles["left"] ?? "0px").dropLast(2)) ?? 0

    let fixedTree = FiberTree(
      layoutView().frame(width: 320, height: 200, alignment: .bottomTrailing)
    ).renderNode
    let fixedChild = firstPlacedChild(in: fixedTree)
    let fixedLeft = Double((fixedChild?.styles["left"] ?? "0px").dropLast(2)) ?? 0
    #expect(fixedTree.styles["width"] == "320px")
    #expect(fixedTree.styles["height"] == "200px")
    #expect(fixedTree.styles["place-items"] == "end")
    #expect(fixedLeft == intrinsicLeft)

    let flexibleTree = FiberTree(
      layoutView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    ).renderNode
    let flexibleChild = firstPlacedChild(in: flexibleTree)
    #expect(flexibleTree.styles["width"] == "100%")
    #expect(flexibleTree.styles["height"] == "100%")
    #expect(flexibleTree.styles["place-items"] == "center")
    #expect(flexibleChild?.styles["left"] == intrinsicChild?.styles["left"])
    #expect(flexibleChild?.styles["top"] == intrinsicChild?.styles["top"])
  }

  @Test
  func splitViewsExposeAxisAndAccessibleResizeDividers() {
    let horizontalLayout = _SplitLayout(axis: .horizontal)
    #expect(horizontalLayout._splitAxis == .horizontal)
    #expect(horizontalLayout._splitDividerThickness == 6)
    #expect(horizontalLayout._swiftUIWebSplitAxisRaw == "horizontal")
    #expect(horizontalLayout._swiftUIWebSplitDividerThickness == 6)
    #expect(_SplitLayout.layoutProperties.stackOrientation == .horizontal)

    let verticalLayout = _SplitLayout(axis: .vertical)
    #expect(verticalLayout._splitAxis == .vertical)
    #expect(verticalLayout._swiftUIWebSplitAxisRaw == "vertical")

    let horizontal = FiberTree(HSplitView {
      Text("Inspector")
      Text("Canvas")
      Text("Details")
    }).renderNode.htmlDescription
    #expect(horizontal.contains("data-split-axis=\"horizontal\""))
    #expect(horizontal.contains("aria-orientation=\"vertical\""))
    #expect(horizontal.contains("aria-label=\"Resize columns\""))
    #expect(horizontal.contains("data-split-divider-size=\"6\""))

    let vertical = FiberTree(VSplitView {
      Text("Top pane")
      Text("Bottom pane")
    }).renderNode.htmlDescription
    #expect(vertical.contains("data-split-axis=\"vertical\""))
    #expect(vertical.contains("aria-orientation=\"horizontal\""))
    #expect(vertical.contains("aria-label=\"Resize rows\""))

    let measured = StaticHTMLFiberRenderer().render(
      HSplitView {
        Text("Measured left")
        Text("Measured right")
      }
      .frame(width: 320, height: 120)
    )
    #expect(measured.contains("data-split-divider-size=\"6\""))
    #expect(measured.contains("data-layout-content-width=\"320\""))
  }

  @Test
  func legacyZStackHandlesEmptyAndNonemptyContent() {
    let empty = FiberTree(ZStack { EmptyView() }).renderNode
    #expect(empty.attributes["data-layout-kind"] == "zstack")
    #expect(empty.children.isEmpty)

    let populated = FiberTree(ZStack(alignment: .topLeading) { Text("Layer") }).renderNode
    #expect(populated.attributes["data-layout-alignment"] == Alignment.topLeading.cssValue)
    #expect(populated.children.count == 1)
    #expect(populated.children.first?.htmlDescription.contains("Layer") == true)
  }
}
