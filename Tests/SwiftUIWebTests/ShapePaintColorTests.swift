import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
import SwiftUIWebCharts
import SwiftUIWebHTML

/// SVG paints carry unresolved SwiftUI colors (semantic tokens, adaptive
/// `light-dark()` colors, opacity mixes). They must reach the browser as CSS
/// declarations, which every engine resolves against the cascade and active
/// color scheme, rather than as presentation attributes.
@Suite
@MainActor
struct ShapePaintColorTests {
  private static let colorForms: [(name: String, color: Color)] = [
    ("named", Color.red),
    ("hex", Color("#00C7BE")),
    ("rgb", Color(red: 0.1, green: 0.2, blue: 0.3)),
    ("css variable", Color("var(--accent)")),
    ("light-dark", Color("light-dark(#ff0000, #0000ff)")),
    ("opacity", Color("light-dark(#ff0000, #0000ff)").opacity(0.5)),
    ("semantic", Color.accentColor),
  ]

  private func elements(named tag: String, in node: _RenderNode) -> [_RenderNode] {
    var found: [_RenderNode] = []
    if case .element(tag) = node.kind { found.append(node) }
    for child in node.children { found += elements(named: tag, in: child) }
    return found
  }

  private func shapePath<V: View>(_ view: V) -> _RenderNode? {
    let root = FiberTree(view, deferLazyCollections: false, rootLayoutProposal: ProposedViewSize(width: 40, height: 40)).renderNode
    return elements(named: "path", in: root).first
  }

  /// The one element that paints a solid fill: a CSS-painted `div` with `background`, not an SVG path.
  private func solidFill<V: View>(_ view: V) -> _RenderNode? {
    let root = FiberTree(view, deferLazyCollections: false, rootLayoutProposal: ProposedViewSize(width: 40, height: 40)).renderNode
    return allNodes(in: root).first { $0.classes.contains("shape-layer") }
  }

  private func allNodes(in node: _RenderNode) -> [_RenderNode] {
    [node] + node.children.flatMap { allNodes(in: $0) }
  }

  @Test
  func testEveryColorFormFillsAShapeThroughCSS() {
    for (name, color) in Self.colorForms {
      let layer = solidFill(Circle().fill(color).frame(width: 40, height: 40))
      #expect(layer?.styles["background"] == color.cssValue, "\(name) background")
      #expect(layer?.attributes["fill"] == nil, "\(name) must not use a presentation attribute")
      #expect(elements(named: "path", in: layer ?? _RenderNode.element("div")).isEmpty, "\(name) solid fill draws no path")
    }
  }

  @Test
  func testStandardColorsResolveAsShapeStyleImplicitMembers() {
    #expect(solidFill(Circle().fill(.red).frame(width: 40, height: 40))?.styles["background"] == Color.red.cssValue)
    #expect(shapePath(Capsule().stroke(.mint, lineWidth: 2).frame(width: 40, height: 40))?.styles["stroke"] == Color.mint.cssValue)
    #expect(solidFill(Rectangle().fill(.clear).frame(width: 40, height: 40))?.styles["background"] == Color.clear.cssValue)
  }

  @Test
  func testEveryColorFormStrokesAndStrokeBordersAShapeThroughCSS() {
    for (name, color) in Self.colorForms {
      let stroked = shapePath(Circle().stroke(color, lineWidth: 3).frame(width: 40, height: 40))
      #expect(stroked?.styles["stroke"] == color.cssValue, "\(name) stroke")
      #expect(stroked?.styles["fill"] == "none", "\(name) fill")
      #expect(stroked?.attributes["stroke"] == nil && stroked?.attributes["fill"] == nil, "\(name)")
      #expect(stroked?.attributes["stroke-width"] == "3", "\(name) geometry stays an attribute")

      let bordered = shapePath(RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: 2).frame(width: 40, height: 40))
      #expect(bordered?.styles["stroke"] == color.cssValue, "\(name) strokeBorder")
      #expect(bordered?.attributes["stroke"] == nil, "\(name) strokeBorder")
    }
  }

  @Test
  func testGradientStopsAndPaintServerReferencesUseCSS() {
    let colors = Self.colorForms.map(\.color)
    let linear = LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    let radial = RadialGradient(colors: colors, center: .center, startRadius: 0, endRadius: 20)
    for view in [AnyView(Circle().fill(linear)), AnyView(Capsule().stroke(radial, lineWidth: 2))] {
      let root = FiberTree(view.frame(width: 40, height: 40), deferLazyCollections: false).renderNode
      let stops = elements(named: "stop", in: root)
      #expect(stops.map { $0.styles["stop-color"] } == colors.map { Optional($0.cssValue) })
      #expect(stops.allSatisfy { $0.attributes["stop-color"] == nil })
      let path = elements(named: "path", in: root).first
      let paint = path?.styles["fill"]?.hasPrefix("url(#paint-gradient-") == true
        || path?.styles["stroke"]?.hasPrefix("url(#paint-gradient-") == true
      #expect(paint, "Gradient paint-server reference must be a CSS paint")
    }
  }

  @Test
  func testAngularWedgesAndTrimmedShapesKeepOneCSSPaintChannel() {
    let angular = AngularGradient(colors: [Color("var(--accent)"), Color("light-dark(white, black)")], center: .center)
    let root = FiberTree(Circle().fill(angular).frame(width: 40, height: 40), deferLazyCollections: false).renderNode
    let paths = elements(named: "path", in: root)
    #expect(paths.count > 2)
    #expect(paths.allSatisfy { $0.attributes["fill"] == nil })
    #expect(paths.contains { $0.styles["fill"]?.contains("var(--accent)") == true })

    let trimmed = shapePath(Circle().trim(from: 0, to: 0.5).stroke(Color("var(--accent)"), lineWidth: 2).frame(width: 40, height: 40))
    #expect(trimmed?.styles["fill"] == "none")
    #expect(trimmed?.styles["stroke"] == "var(--accent)")
    #expect(trimmed?.attributes["fill"] == nil)
  }

  @Test
  func testChartSeriesPaintUsesCSS() {
    let adaptive = Color("light-dark(#ff0000, #0000ff)")
    let chart = Chart {
      LineMark(x: .value("Day", 1), y: .value("Count", 2)).foregroundStyle(adaptive)
      LineMark(x: .value("Day", 2), y: .value("Count", 4)).foregroundStyle(adaptive)
    }
    let html = StaticHTMLFiberRenderer().render(chart.frame(width: 200, height: 100))
    #expect(html.contains("stroke: light-dark(#ff0000, #0000ff)"), "Chart series color must be a CSS paint")
    #expect(!html.contains("stroke=\"light-dark("))
  }

  /// Apple: `Circle().fill(.red).stroke(.blue, lineWidth: 1)` chains the View
  /// modifier `stroke(_:lineWidth:)` on the paint view. The paint view's
  /// storage must not shadow that method.
  @Test
  func testFillThenStrokeChainsTheViewModifier() {
    let view = Circle().fill(Color.red).stroke(Color.blue, lineWidth: 1).frame(width: 40, height: 40)
    let root = FiberTree(view, deferLazyCollections: false, rootLayoutProposal: ProposedViewSize(width: 40, height: 40)).renderNode
    let paths = elements(named: "path", in: root)
    // A solid fill is the CSS background of its box; the stroke stays a path.
    #expect(allNodes(in: root).contains { $0.styles["background"] == Color.red.cssValue }, "fill layer keeps its paint")
    #expect(paths.contains { $0.styles["stroke"] == Color.blue.cssValue }, "stroke layer carries the chained paint")
  }

  /// Apple's `ShapeView`: `fill`, `stroke` and `strokeBorder` stack over a painted shape, in any order.
  @Test
  func testShapeViewStacksFillAndStrokeLayersOnOneShape() {
    func takesShapeView<V: ShapeView>(_ view: V) -> V.Content.Type { V.Content.self }
    _ = takesShapeView(Circle().fill(Color.red).stroke(Color.blue, lineWidth: 2))
    _ = takesShapeView(Circle().stroke(Color.blue, lineWidth: 2).fill(Color.red))
    _ = takesShapeView(Circle().fill(Color.red).strokeBorder(Color.blue, lineWidth: 2))
    _ = takesShapeView(Circle().fill(Color.red).stroke(Color.blue, style: StrokeStyle(lineWidth: 2)))

    let stacked = Circle().fill(Color.red).stroke(Color.blue, lineWidth: 2).frame(width: 40, height: 40)
    let root = FiberTree(stacked, deferLazyCollections: false, rootLayoutProposal: ProposedViewSize(width: 40, height: 40)).renderNode
    let paths = elements(named: "path", in: root)
    #expect(allNodes(in: root).contains { $0.styles["background"] == Color.red.cssValue }, "the fill is painted first")
    #expect(paths.contains { $0.styles["stroke"] == Color.blue.cssValue && $0.attributes["stroke-width"] == "2" }, "the stroke is painted over it")

    let bordered = Circle().stroke(Color.blue, lineWidth: 2).fill(Color.red).frame(width: 40, height: 40)
    let borderedRoot = FiberTree(bordered, deferLazyCollections: false, rootLayoutProposal: ProposedViewSize(width: 40, height: 40)).renderNode
    #expect(allNodes(in: borderedRoot).contains { $0.styles["background"] == Color.red.cssValue }, "a fill over a stroke keeps its paint")
  }

  /// Apple's `Shape.stroke(style:)` and `stroke(lineWidth:)` return a Shape. Filling that shape strokes it with the
  /// fill's paint, and as a view it strokes with the default foreground paint, as the old `stroke(lineWidth:)` did.
  @Test
  func testStrokedOutlineIsAShapeThatFillsAsAStroke() {
    func takesShape<S: Shape>(_ shape: S) -> S { shape }
    _ = takesShape(Circle().stroke(lineWidth: 2))
    _ = takesShape(Circle().stroke(style: StrokeStyle(lineWidth: 3, dash: [4])))

    let filled = Circle().stroke(lineWidth: 2).fill(Color.red).frame(width: 40, height: 40)
    let root = FiberTree(filled, deferLazyCollections: false, rootLayoutProposal: ProposedViewSize(width: 40, height: 40)).renderNode
    let paths = elements(named: "path", in: root)
    #expect(paths.contains { $0.styles["stroke"] == Color.red.cssValue && $0.attributes["stroke-width"] == "2" }, "filling a stroke paints the stroke")
    #expect(!paths.contains { $0.styles["fill"] == Color.red.cssValue }, "the stroked outline is not filled")

    let plain = Circle().stroke(lineWidth: 2).frame(width: 40, height: 40)
    let plainRoot = FiberTree(plain, deferLazyCollections: false, rootLayoutProposal: ProposedViewSize(width: 40, height: 40)).renderNode
    #expect(elements(named: "path", in: plainRoot).contains { $0.styles["stroke"] == "currentColor" && $0.attributes["stroke-width"] == "2" }, "the view strokes with the foreground style")
  }

  /// Apple's instance levels: `color.secondary` is the receiver at the second level, with the static levels' strength.
  @Test
  func testShapeStyleInstanceLevelsMixTheReceiverAtTheStaticStrengths() {
    func mixed(_ percent: Int) -> String { "color-mix(in srgb, \(Color.red._swiftUIWebCSSValue) \(percent)%, transparent)" }
    #expect(Color.red.secondary._swiftUIWebCSSValue == mixed(60))
    #expect(Color.red.tertiary._swiftUIWebCSSValue == mixed(30))
    #expect(Color.red.quaternary._swiftUIWebCSSValue == mixed(18))
    #expect(Color.red.quinary._swiftUIWebCSSValue == mixed(10))
  }

  /// `ShapeStyle.opacity(_:)` and `shadow(_:)` return wrappers whose storage must not be named after the
  /// modifier: a stored `opacity` would shadow the method, so `.opacity(a).opacity(b)` would not compile.
  @Test
  func testChainedShapeStyleModifiersResolveToMethods() {
    func faded<S: ShapeStyle>(_ style: S) -> _OpacityShapeStyle<_OpacityShapeStyle<S>> {
      style.opacity(0.5).opacity(0.5)
    }
    func shadowed<S: ShapeStyle>(_ style: S) -> _ShadowShapeStyle<_ShadowShapeStyle<S>> {
      style.shadow(.drop(radius: 1)).shadow(.drop(radius: 2))
    }
    let css = faded(Color.red)._swiftUIWebCSSValue
    #expect(css.hasPrefix("color-mix(in srgb, color-mix("), "nested opacity wraps the inner mix")
    #expect(shadowed(Color.red)._swiftUIWebShadow != nil, "chained shadow keeps a shadow")
  }
}
