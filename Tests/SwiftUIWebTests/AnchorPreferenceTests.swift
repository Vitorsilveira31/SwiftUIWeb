import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

/// Anchors and the preferences that carry them (`AnchorPreferences.swift`): a view's geometry read in another view's
/// coordinates, the layers drawn from a subtree's preference, `transformPreference`, a text's `Text.LayoutKey`, and the
/// attributes of a matched geometry.
@Suite
@MainActor
struct AnchorPreferenceTests {
  @Test
  func anAnchorResolvesInTheCoordinatesOfTheViewThatReadsIt() {
    let frame = CGRect(x: 10, y: 20, width: 30, height: 40)
    #expect(Anchor<CGPoint>.Source.topLeading._make(frame)._value(from: CGPoint(x: 4, y: 5)) == CGPoint(x: 6, y: 15))
    #expect(Anchor<CGPoint>.Source.bottomTrailing._make(frame)._value(from: .zero) == CGPoint(x: 40, y: 60))
    #expect(Anchor<CGPoint>.Source.point(CGPoint(x: 1, y: 2))._make(frame)._value(from: .zero) == CGPoint(x: 11, y: 22))
    #expect(Anchor<CGRect>.Source.bounds._make(frame)._value(from: CGPoint(x: 10, y: 10)) == CGRect(x: 0, y: 10, width: 30, height: 40))
    #expect(Anchor<CGRect>.Source.rect(CGRect(x: 1, y: 1, width: 2, height: 2))._make(frame)._value(from: .zero) == CGRect(x: 11, y: 21, width: 2, height: 2))
    let both = Anchor<[CGPoint]>.Source([.topLeading, .center])._make(frame)._value(from: .zero)
    #expect(both == [CGPoint(x: 10, y: 20), CGPoint(x: 25, y: 40)])
    let none = Anchor<CGPoint?>.Source(nil as Anchor<CGPoint>.Source?)._make(frame)._value(from: .zero)
    #expect(none == nil)
    #expect(Anchor<CGPoint>.Source.center._make(frame) == Anchor<CGPoint>.Source.center._make(frame))
  }

  @Test
  func anOverlayReadsTheAnchorOfItsSubtreeInItsOwnCoordinates() throws {
    let tree = FiberTree(Anchored())
    defer { tree._dispose() }
    #expect(tree.renderNode.htmlDescription.contains("at 0,0,0"))
    // The page measures the anchored view in the window: the overlay draws again with its frame.
    let anchored = try #require(tree.findNode(withEvent: "geometryChange"))
    #expect(anchored.attributes["data-geometry-change-position"] == "true")
    tree.dispatch(event: "geometryChange", value: "10,20,30,40", on: anchored)
    #expect(tree.renderNode.htmlDescription.contains("at 10,20,30"))
    // A reader measured at 4,5 reads the frame from there.
    let reader = try #require(tree.findNode(withEvent: "geometry"))
    tree.dispatch(event: "geometry", value: "4,5,30,40", on: reader)
    #expect(tree.renderNode.htmlDescription.contains("at 6,15,30"))
  }

  @Test
  func eachLayerReadsOnlyItsOwnSubtree() {
    let html = FiberTree(Siblings()).renderNode.htmlDescription
    #expect(html.contains("first 1"))
    #expect(html.contains("second 5"))
    #expect(html.contains("both 6"))
  }

  @Test
  func transformPreferenceChangesTheValueOfTheSubtree() {
    let html = FiberTree(Transformed()).renderNode.htmlDescription
    #expect(html.contains("total 50"))
    #expect(html.contains("background 50"))
  }

  @Test
  func aTextGivesItsLayoutToAReaderAbove() throws {
    let tree = FiberTree(LaidOut())
    defer { tree._dispose() }
    // Asked for by the reader, the text is measured; the text of the layer is not.
    let before = tree.renderNode.htmlDescription
    #expect(before.contains("lines none"))
    #expect(before.components(separatedBy: "data-text-layout").count == 2)
    let text = try #require(tree.findNode(withEvent: "textLayout"))
    tree.dispatch(event: "textLayout", value: twoRuns, on: text)
    #expect(tree.renderNode.htmlDescription.contains("lines 1 runs 2 origin 0,0"))
    // The text's origin, measured in the window, is where its anchor points.
    let measured = try #require(tree.findNode(withEvent: "geometryChange"))
    tree.dispatch(event: "geometryChange", value: "5,6,100,40", on: measured)
    #expect(tree.renderNode.htmlDescription.contains("origin 5,6"))
    // Not drawn by a renderer, it keeps its own glyphs.
    #expect(!tree.renderNode.htmlDescription.contains("-webkit-text-fill-color"))
  }

  @Test
  func aTextWithoutAReaderIsNotMeasured() {
    let html = FiberTree(Text("plain")).renderNode.htmlDescription
    #expect(!html.contains("data-text-layout"))
  }

  @Test
  func matchedGeometryPublishesItsPropertiesAndAnchor() {
    let html = FiberTree(Matched()).renderNode.htmlDescription
    #expect(html.contains("data-matched-source=\"vt-"))
    #expect(html.contains("data-matched-target=\"vt-"))
    #expect(html.contains("data-matched-properties=\"position\""))
    #expect(html.contains("data-matched-anchor=\"0 0\""))
    #expect(MatchedGeometryProperties.frame == [.position, .size])
    #expect(MatchedGeometryProperties.frame.rawValue == 3)
  }
}

private struct BoundsKey: PreferenceKey {
  static var defaultValue: [Anchor<CGRect>] { [] }
  static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) { value.append(contentsOf: nextValue()) }
}

private struct CountKey: PreferenceKey {
  static var defaultValue: Int { 0 }
  static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

private struct Anchored: View {
  var body: some View {
    Text("box")
      .anchorPreference(key: BoundsKey.self, value: .bounds) { [$0] }
      .overlayPreferenceValue(BoundsKey.self) { anchors in
        GeometryReader { proxy in
          Text(anchors.map { anchor in
            let rect = proxy[anchor]
            return "at \(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.size.width))"
          }.joined())
        }
      }
  }
}

private struct Siblings: View {
  var body: some View {
    VStack {
      Text("a").preference(key: CountKey.self, value: 1)
        .overlayPreferenceValue(CountKey.self) { Text("first \($0)") }
      VStack {
        Text("b").preference(key: CountKey.self, value: 2)
        Text("c").preference(key: CountKey.self, value: 3)
      }
      .overlayPreferenceValue(CountKey.self) { Text("second \($0)") }
    }
    .backgroundPreferenceValue(CountKey.self, alignment: .topLeading) { Text("both \($0)") }
  }
}

private struct Transformed: View {
  var body: some View {
    VStack {
      VStack {
        Text("b").preference(key: CountKey.self, value: 2)
        Text("c").preference(key: CountKey.self, value: 3)
      }
      .transformPreference(CountKey.self) { $0 *= 10 }
      .overlayPreferenceValue(CountKey.self) { Text("total \($0)") }
    }
    .backgroundPreferenceValue(CountKey.self) { Text("background \($0)") }
  }
}

private struct LaidOut: View {
  var body: some View {
    (Text("ab") + Text("c").bold())
      .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
        GeometryReader { proxy in
          if let first = layouts.first {
            let origin = proxy[first.origin]
            Text("lines \(first.layout.count) runs \(first.layout.first?.count ?? 0) origin \(Int(origin.x)),\(Int(origin.y))")
          } else {
            Text("lines none")
          }
        }
      }
  }
}

private struct Matched: View {
  @Namespace private var namespace
  var body: some View {
    VStack {
      Text("source").matchedGeometryEffect(id: "pill", in: namespace)
      Text("target").matchedGeometryEffect(id: "pill", in: namespace, properties: .position, anchor: .topLeading, isSource: false)
    }
  }
}
