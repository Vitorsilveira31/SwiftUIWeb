import Foundation
import Testing
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures

/// A run of frame, padding and fixedSize modifiers shares one element (`_SemanticLayers`); the layout host describes it as the
/// chain of wrapper elements the modifiers used to make (`Tools/test-layout-layers-browser.mjs`). These tests pin the Swift side.
@Suite
@MainActor
final class SemanticLayerTests {
  private func render<V: View>(_ view: V) -> _RenderNode { view._render(in: _RenderContext()) }

  private func elementCount(_ node: _RenderNode) -> Int {
    1 + node.children.reduce(0) { $0 + elementCount($1) }
  }

  /// The wrapper chain a view makes with merging off, for comparison.
  private func unmerged<V: View>(_ view: V) -> _RenderNode {
    _SemanticLayers.isEnabled = false
    defer { _SemanticLayers.isEnabled = true }
    return render(view)
  }

  @Test
  func testFrameAroundPaddingIsOneElement() {
    let node = render(Text("Title").padding(12).frame(maxWidth: .infinity, alignment: .leading))
    _expectEqual(node.attributes["data-layout-kind"], "frame")
    _expectEqual(node.attributes["data-frame-max-w"], "inf")
    _expectEqual(node.attributes["data-align-x"], "0")
    _expectEqual(node.attributes["data-layout-wrap"], "padding;padding-bottom=12.0;padding-leading=12.0;padding-top=12.0;padding-trailing=12.0")
    // The element's children are the content's: the padding wrapper is a layer of the frame's element.
    _expectEqual(node.children.count, 1)
    _expectEqual(node.children.first?.kind, .text)
    _expectEqual(elementCount(node) + 1, elementCount(unmerged(Text("Title").padding(12).frame(maxWidth: .infinity, alignment: .leading))))
  }

  @Test
  func testPaddingAroundPaddingAddsUp() {
    let node = render(Text("x").padding(.horizontal, 6).padding(.vertical, 4).padding(.leading, 2))
    _expectEqual(node.attributes["data-layout-kind"], "padding")
    _expectEqual(node.attributes["data-layout-wrap"], nil)
    _expectEqual(node.attributes["data-padding-leading"], "8.0")
    _expectEqual(node.attributes["data-padding-trailing"], "6.0")
    _expectEqual(node.attributes["data-padding-top"], "4.0")
    _expectEqual(node.attributes["data-padding-bottom"], "4.0")
    _expectEqual(node.children.first?.kind, .text)
    _expectEqual(node.styles["padding-inline-start"], "8px")
    _expectEqual(node.styles["padding-top"], "4px")
    // All four edges the same become the shorthand again.
    let uniform = render(Text("x").padding(.horizontal, 3).padding(.vertical, 3))
    _expectEqual(uniform.styles["padding"], "3px")
    _expectEqual(uniform.styles["padding-top"], nil)
  }

  @Test
  func testEdgeInsetsPaddingIsOneElement() {
    let node = render(Text("x").padding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)))
    _expectEqual(node.attributes["data-layout-kind"], "padding")
    _expectEqual(node.attributes["data-padding-top"], "1.0")
    _expectEqual(node.attributes["data-padding-trailing"], "4.0")
    _expectEqual(node.children.first?.kind, .text)
  }

  @Test
  func testNegativePaddingIsNotAdded() {
    let node = render(Text("x").padding(.leading, -4).padding(.leading, 10))
    _expectEqual(node.attributes["data-layout-kind"], "padding")
    _expectEqual(node.attributes["data-layout-wrap"], "padding;padding-leading=-4.0")
    _expectEqual(node.attributes["data-padding-leading"], "10.0")
  }

  @Test
  func testAWrapperWithSomethingOnItIsNotShared() {
    // An event, an identity, a background and an accessibility label belong to the box of the wrapper they were put on.
    let tapped = render(Text("x").padding(4).onTapGesture {}.frame(width: 10))
    _expectEqual(tapped.attributes["data-layout-kind"], "frame")
    _expectEqual(tapped.attributes["data-layout-wrap"], nil)
    let labelled = render(Text("x").padding(4).accessibilityLabel("hello").frame(width: 10))
    _expectEqual(labelled.attributes["data-layout-wrap"], nil)
    let filled = render(Text("x").padding(4).background(Color.red).frame(width: 10))
    _expectEqual(filled.attributes["data-layout-wrap"], nil)
    let identified = render(Text("x").padding(4).id("row").frame(width: 10))
    _expectEqual(identified.attributes["data-layout-wrap"], nil)
    let clipped = render(Text("x").padding(4).cornerRadius(6).frame(width: 10))
    _expectEqual(clipped.attributes["data-layout-wrap"], nil)
  }

  @Test
  func testInheritedStylesDoNotStopSharing() {
    let node = render(Text("x").padding(4).foregroundColor(.red).opacity(0.5).frame(width: 10))
    _expectEqual(node.attributes["data-layout-wrap"] != nil, true)
  }

  @Test
  func testLayersListEveryModifierOutermostFirst() {
    let node = render(Text("x").padding(2).fixedSize().frame(maxWidth: .infinity).padding(.top, 5))
    let kinds = _SemanticLayers.layers(of: node).map(\.kind)
    _expectEqual(kinds, ["padding", "frame", "fixed", "padding"])
  }

  @Test
  func testSplitViewPanesKeepTheirWrapperElements() {
    // The panes of a split view are laid out with CSS, not by the layout host: each wrapper keeps the CSS that is the layout.
    func anyLayer(_ node: _RenderNode) -> Bool {
      node.attributes["data-layout-wrap"] != nil || node.children.contains(where: anyLayer)
    }
    let split = render(HSplitView {
      Text("a").padding(6).frame(maxWidth: .infinity, alignment: .leading)
      Text("b").frame(width: 20).padding(2)
    })
    _expectFalse(anyLayer(split))
    _expectTrue(anyLayer(render(VStack { Text("a").padding(6).frame(maxWidth: .infinity, alignment: .leading) })))
  }

  @Test
  func testMergingOffRestoresTheWrapperElements() {
    let view = Text("x").padding(4).frame(width: 40).padding(1)
    _expectTrue(elementCount(render(view)) < elementCount(unmerged(view)))
    _expectEqual(unmerged(view).attributes["data-layout-wrap"], nil)
  }

  @Test
  func testMeasurementOfAMergedChainEqualsTheWrapperElements() {
    // A custom Layout measures its subviews in Swift from their styles; a chain must measure as its wrapper elements did.
    struct Probe: Layout {
      func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var out = CGSize.zero
        for subview in subviews {
          let size = subview.sizeThatFits(proposal)
          out.width += size.width
          out.height = max(out.height, size.height)
        }
        return out
      }
      func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: proposal) }
      }
    }
    func sizes<V: View>(_ make: () -> V) -> String {
      let node = render(Probe { make() })
      var found: [String] = []
      func walk(_ n: _RenderNode) {
        if n.styles["position"] == "absolute", let width = n.styles["width"], let height = n.styles["height"], let left = n.styles["left"], let top = n.styles["top"] { found.append(left + "," + top + " " + width + "x" + height) }
        n.children.forEach(walk)
      }
      walk(node)
      return found.joined(separator: ",")
    }
    let views: [() -> AnyView] = [
      { AnyView(Text("abc").padding(8).frame(width: 100, height: 40)) },
      { AnyView(Text("abc").frame(width: 50).padding(.horizontal, 6).frame(maxWidth: .infinity)) },
      { AnyView(Text("abc").fixedSize().padding(3).frame(minWidth: 10, maxWidth: 90)) },
      { AnyView(Text("abc").frame(height: 30).frame(width: 70).padding(2)) },
    ]
    for make in views {
      _SemanticLayers.isEnabled = true
      let merged = sizes(make)
      _SemanticLayers.isEnabled = false
      let chain = sizes(make)
      _SemanticLayers.isEnabled = true
      _expectFalse(merged.isEmpty)
      _expectEqual(merged, chain)
    }
  }

  /// The layout attributes and the measured styles of a wrapper element.
  private func signature(_ node: _RenderNode) -> String {
    let measured = ["width", "height", "min-width", "min-height", "max-width", "max-height"]
    let attributes = node.attributes.filter { name, _ in
      name == "data-layout-kind" || name == "data-align-x" || name == "data-align-y" || name.hasPrefix("data-padding-")
        || name.hasPrefix("data-fixed-") || (name.hasPrefix("data-frame-") && name != "data-frame-alignment")
    }
    return attributes.keys.sorted().map { $0 + "=" + attributes[$0]! }.joined(separator: " ") + " | "
      + measured.compactMap { node.styles[$0].map { $0 } == nil ? nil : $0 + ":" + node.styles[$0]! }.joined(separator: ";")
  }

  /// The wrapper elements of a chain, outermost first, down to the first element that is not a layout wrapper.
  private func wrapperChain(_ node: _RenderNode) -> [String] {
    var out: [String] = []
    var current = node
    while let kind = current.attributes["data-layout-kind"], _SemanticLayers.isLayerKind(kind) {
      out.append(signature(current))
      guard current.children.count == 1 else { break }
      current = current.children[0]
    }
    return out
  }

  @Test
  func testUnfoldedChainEqualsTheWrapperElements() {
    // Merging, then unfolding, gives back the wrapper elements the modifiers make: the same layout attributes and the same
    // sizing styles, level by level.
    let views: [() -> AnyView] = [
      { AnyView(Text("x").padding(8).frame(width: 100, height: 40)) },
      { AnyView(Text("x").frame(width: 100, height: 40).padding(8)) },
      { AnyView(Text("x").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).frame(height: 44)) },
      { AnyView(Text("x").fixedSize(horizontal: true, vertical: false).padding(3).frame(minWidth: 10, idealWidth: 20, maxWidth: 90, minHeight: 5, idealHeight: 15, maxHeight: .infinity)) },
      { AnyView(Text("x").frame(width: 50, height: 20).frame(maxWidth: .infinity).frame(maxHeight: .infinity, alignment: .top)) },
      { AnyView(Text("x").padding(.top, 2).frame(width: 9).padding(.leading, 5).fixedSize()) },
      { AnyView(Text("x").frame(maxWidth: .infinity, alignment: .trailing).frame(maxWidth: 620, alignment: .leading).padding().frame(maxWidth: .infinity, alignment: .center)) },
    ]
    for make in views {
      _SemanticLayers.isEnabled = true
      let merged = render(make())
      _SemanticLayers.isEnabled = false
      let chain = render(make())
      _SemanticLayers.isEnabled = true
      let expected = wrapperChain(chain)
      _expectFalse(expected.isEmpty)
      _expectEqual(wrapperChain(_SemanticLayers.unfolded(merged)), expected)
    }
  }

  @Test
  func testLayerStylesMatchTheModifiers() {
    // `styles(of:)` gives back what the modifier put on its wrapper, for the properties a measurement reads.
    let frames: [StyleModifier] = [
      _frameModifier(width: 10, height: nil, alignment: .center),
      _frameModifier(width: nil, height: 20, alignment: .leading),
      _frameModifier(width: 30, height: 40, maxWidth: .infinity, maxHeight: .infinity, alignment: .center),
      _frameModifier(width: nil, height: nil, maxWidth: 80, maxHeight: .infinity, alignment: .center),
      _frameModifier(maxWidth: .infinity, maxHeight: nil, alignment: .trailing),
      _frameModifier(maxWidth: 12, maxHeight: 14, alignment: .center),
      _frameModifier(minWidth: 1, idealWidth: 2, maxWidth: nil, minHeight: 3, idealHeight: 4, maxHeight: nil, alignment: .center),
      _frameModifier(minWidth: 1, idealWidth: 2, maxWidth: 9, minHeight: 3, idealHeight: 4, maxHeight: .infinity, alignment: .center),
      _fixedSizeModifier(horizontal: true, vertical: false),
      _fixedSizeModifier(horizontal: true, vertical: true),
    ]
    let measured = ["width", "height", "min-width", "min-height", "max-width", "max-height"]
    for modifier in frames {
      let kind = modifier.semantic["data-layout-kind"] ?? ""
      let layer = _SemanticLayers.Layer(kind: kind, semantic: modifier.semantic)
      let derived = _SemanticLayers.styles(of: layer)
      for name in measured { _expectEqual(derived[name], modifier.styles[name]) }
    }
  }

  // MARK: - Shapes the CSS layout lays out

  @Test
  func testSeveralViewsInAHandBuiltWrapperAreOneVStack() {
    // A Section's header and footer sit in a padding wrapper; two views there are stacked as the layout host did (`@group`).
    let node = render(Section { Text("row") } header: { Text("h1"); Text("h2") } footer: { Text("f1"); Text("f2") })
    func wrappers(_ node: _RenderNode, _ out: inout [_RenderNode]) {
      if node.classes.contains("section-heading") || node.classes.contains("section-trailer") { out.append(node) }
      for child in node.children { wrappers(child, &out) }
    }
    var found: [_RenderNode] = []
    wrappers(node, &found)
    _expectEqual(found.count, 2)
    for padding in found {
      _expectEqual(padding.attributes["data-layout-kind"], "padding")
      _expectEqual(padding.children.count, 1)
      let stack = padding.children[0]
      _expectEqual(stack.attributes["data-layout-kind"], "vstack")
      _expectEqual(stack.attributes["data-layout-gap"], "0.0")
      _expectEqual(stack.attributes["data-align-x"], "0")
      _expectEqual(stack.children.first?.children.count, 2)
    }
    // One view needs no stack.
    var single: [_RenderNode] = []
    wrappers(render(Section { Text("row") } header: { Text("h") } footer: { Text("f") }), &single)
    _expectEqual(single.count, 2)
    for padding in single { _expectEqual(padding.children.first?.kind, .text) }
  }

  @Test
  func testHeldViewsLookThroughGroupsAndEmptyViews() {
    func group(_ views: [_RenderNode]) -> _RenderNode { let node = _RenderNode.fragment(); node.children = views; return node }
    let one = _RenderNode.text("a"), two = _RenderNode.text("b"), three = _RenderNode.text("c")
    // Nested groups count their views, and the empty ones none.
    let several = group([one, group([two, _RenderNode(kind: .empty), three])])
    let held = _semanticHeld(several)
    _expectEqual(held.count, 1)
    _expectEqual(held[0].attributes["data-layout-kind"], "vstack")
    _expectTrue(held[0].children.first === several)
    let lone = group([_RenderNode(kind: .empty), group([one])])
    _expectTrue(_semanticHeld(lone).first === lone)
    _expectTrue(_semanticHeld(one).first === one)
  }

  @Test
  func testAModifierOnAGroupWrapsEachViewOnItsOwn() {
    // As in SwiftUI, a frame on a Group is a frame on each view: the wrapper holds one view, never several.
    let node = render(Group { Text("a"); Text("b") }.frame(width: 50))
    let wrapped = node.kind == .fragment ? node.children.flatMap { $0.kind == .fragment ? $0.children : [$0] } : [node]
    _expectEqual(wrapped.count, 2)
    for frame in wrapped {
      _expectEqual(frame.attributes["data-layout-kind"], "frame")
      _expectEqual(frame.children.count, 1)
    }
  }

  @Test
  func testAChainOfTwoFixedFramesInsideAFrameKeepsItsWrapper() {
    // Two boxes on one axis (the 30 and the 60 point frame) cannot share the box of the 100 point frame.
    let node = render(Text("x").frame(width: 30).frame(width: 60).frame(width: 100))
    _expectEqual(node.attributes["data-frame-w"], "100.0")
    _expectEqual(node.attributes["data-layout-wrap"], nil)
    let inner = node.children[0]
    _expectEqual(inner.attributes["data-frame-w"], "60.0")
    _expectTrue(inner.attributes["data-layout-wrap"]?.hasPrefix("frame;") == true)
    _expectEqual(inner.children.first?.kind, .text)
    // The first two do fold: one element holds both.
    let pair = render(Text("x").frame(width: 30).frame(width: 60))
    _expectEqual(pair.attributes["data-frame-w"], "60.0")
    _expectEqual(pair.children.first?.kind, .text)
    _expectTrue(pair.attributes["data-layout-wrap"] != nil)
  }

  @Test
  func testAFillingMinimumLargerThanItsFixedFrameKeepsItsWrapper() {
    // The 160 point minimum overflows the 100 point frame: CSS has no plan for that chain, so it stays two elements.
    let overflowing = render(Text("x").frame(minWidth: 160, maxWidth: .infinity).frame(width: 100))
    _expectEqual(overflowing.attributes["data-layout-wrap"], nil)
    _expectEqual(overflowing.children.first?.attributes["data-frame-min-w"], "160.0")
    // Inside a frame as wide as the minimum it merges.
    let fits = render(Text("x").frame(minWidth: 160, maxWidth: .infinity).frame(width: 200))
    _expectTrue(fits.attributes["data-layout-wrap"] != nil)
    _expectEqual(fits.children.first?.kind, .text)
  }

  @Test
  func testAPaddingInsideABoxStopsTheChain() {
    // A padding inside a box makes the margin of its child: nothing else may follow it inside the box.
    let layers = ["frame;frame-w=50", "padding;padding-top=4", "frame;frame-h=20"].map { _SemanticLayers.decode($0)[0] }
    _expectFalse(_SemanticLayers.isFoldable([_SemanticLayers.Layer(kind: "frame", fields: [("frame-max-w", "inf")])] + layers))
    _expectTrue(_SemanticLayers.isFoldable([_SemanticLayers.Layer(kind: "frame", fields: [("frame-max-w", "inf")])] + layers.prefix(2)))
  }

  @Test
  func testUnfoldableChainsAreTheOnesCSSRefuses() {
    // The layers of `Tools/test-css-layout-layers.mjs`, every chain of up to four: the number of the ones that the CSS layout
    // refuses as one box is printed there, and Swift must keep exactly those chains apart.
    typealias Fields = [(name: String, value: String)]
    let padded: Fields = [("padding-top", "8.0"), ("padding-leading", "8.0"), ("padding-bottom", "8.0"), ("padding-trailing", "8.0")]
    let layers: [(kind: String, fields: Fields)] = [
      ("frame", [("frame-w", "120"), ("frame-h", "60")]),
      ("frame", [("frame-max-w", "inf")]),
      ("frame", [("frame-min-h", "44"), ("frame-max-h", "inf")]),
      ("frame", [("frame-max-w", "300")]),
      ("frame", [("frame-min-w", "160")]),
      ("padding", padded),
      ("padding", [("padding-leading", "12.0"), ("padding-trailing", "4.0")]),
      ("padding", [("padding-top", "0.3"), ("padding-leading", "0.7"), ("padding-bottom", "0.37"), ("padding-trailing", "0.1")]),
      ("fixed", [("fixed-x", "true"), ("fixed-y", "false")]),
    ]
    var unfoldable = 0, chains = 0
    func extend(_ chain: [_SemanticLayers.Layer]) {
      if !chain.isEmpty {
        chains += 1
        if !_SemanticLayers.isFoldable(chain) { unfoldable += 1 }
      }
      if chain.count < 4 { for layer in layers { extend(chain + [_SemanticLayers.Layer(kind: layer.kind, fields: layer.fields)]) } }
    }
    extend([])
    _expectEqual(chains, 7380)
    _expectEqual(unfoldable, 2919)
  }
}
