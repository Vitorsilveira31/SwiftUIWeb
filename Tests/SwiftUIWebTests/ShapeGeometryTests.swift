import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
import SwiftUIWebHTML

/// Shapes are laid out after they are rendered, so their DOM geometry must not
/// bake a nominal size into the corners: a 100x100 SVG path stretched to a
/// 94x44 box turns a circular corner elliptical. Corners are CSS radii, circles
/// fit the shorter side, and shadows follow the shape.
@Suite
@MainActor
struct ShapeGeometryTests {
  private func elements(named tag: String, in node: _RenderNode) -> [_RenderNode] {
    var found: [_RenderNode] = []
    if case .element(tag) = node.kind { found.append(node) }
    for child in node.children { found += elements(named: tag, in: child) }
    return found
  }

  /// Renders without any frame, so the shape has no explicit proposal.
  private func render<V: View>(_ view: V) -> _RenderNode {
    FiberTree(view, deferLazyCollections: false).renderNode
  }

  private func shapeSVG(_ node: _RenderNode) -> _RenderNode? {
    elements(named: "svg", in: node).first { $0.classes.contains("shape-layer") }
  }

  /// The first shape element whatever it is: a `div` for a CSS-painted solid fill, an `svg` otherwise.
  private func shapeLayer(_ node: _RenderNode) -> _RenderNode? {
    if node.classes.contains("shape-layer") { return node }
    for child in node.children { if let found = shapeLayer(child) { return found } }
    return nil
  }

  @Test
  func testRoundedRectangleBackgroundKeepsCircularCornersWithoutFrame() throws {
    let node = render(
      Text("Para você").frame(minHeight: 44).padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.red))
    )
    // A solid fill is one CSS box: no SVG and no path, so no arcs to stretch.
    let layer = try #require(shapeLayer(node))
    #expect(layer.kind == .element("div"))
    #expect(layer.styles["background"] == Color.red.cssValue)
    #expect(layer.styles["border-radius"] == "22px")
    #expect(layer.styles["overflow"] == "hidden")
    #expect(layer.attributes["data-shape-geometry"] == "css-radius")
    #expect(elements(named: "path", in: layer).isEmpty)
    // The path stays inspectable for masks and diagnostics.
    #expect(layer.attributes["data-shape-path"]?.isEmpty == false)
  }

  @Test
  func testCapsuleFillIsFullyRoundedAtAnySize() throws {
    let layer = try #require(shapeLayer(render(Capsule().fill(Color.blue))))
    #expect(layer.kind == .element("div"))
    #expect(layer.styles["border-radius"] == "9999px")
    #expect(layer.styles["overflow"] == "hidden")
    #expect(elements(named: "path", in: layer).isEmpty)
  }

  @Test
  func testRectangleFillIsOneBoxWithoutCorners() throws {
    let layer = try #require(shapeLayer(render(Rectangle().fill(Color.red))))
    #expect(layer.kind == .element("div"))
    #expect(layer.styles["background"] == Color.red.cssValue)
    #expect(layer.styles["border-radius"] == nil)
    #expect(elements(named: "path", in: layer).isEmpty)
  }

  @Test
  func testSolidCircleIsCSSOnlyInASquareBox() throws {
    let square = try #require(shapeLayer(FiberTree(Circle().fill(Color.red).frame(width: 20, height: 20), deferLazyCollections: false).renderNode))
    #expect(square.kind == .element("div"))
    #expect(square.styles["border-radius"] == "9999px")
    // A box of unequal sides would turn CSS corners into an ellipse, and an unframed circle has no box yet.
    let wide = try #require(shapeSVG(FiberTree(Circle().fill(Color.red).frame(width: 200, height: 100), deferLazyCollections: false).renderNode))
    #expect(wide.attributes["preserveAspectRatio"] == "xMidYMid meet")
    #expect(shapeSVG(render(Circle().fill(Color.red))) != nil)
  }

  @Test
  func testFillsThatCSSCannotDrawKeepTheSVGPath() throws {
    let gradient = try #require(shapeSVG(render(
      RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
    )))
    #expect(gradient.styles["border-radius"] == "8px")
    #expect(!elements(named: "path", in: gradient).isEmpty)
    let evenOdd = try #require(shapeSVG(render(RoundedRectangle(cornerRadius: 8).fill(Color.red, style: FillStyle(eoFill: true)))))
    #expect(evenOdd.attributes["data-shape-geometry"] == "css-radius")
    let insetRectangle = try #require(shapeSVG(render(Rectangle().inset(by: 4).fill(Color.red))))
    #expect(!elements(named: "path", in: insetRectangle).isEmpty)
    let unantialiased = try #require(shapeSVG(render(Capsule().fill(Color.red, style: FillStyle(antialiased: false)))))
    // Unantialiased fills need `shape-rendering`, which CSS cannot express: the path stays.
    #expect(!elements(named: "path", in: unantialiased).isEmpty)
  }

  @Test
  func testCapsuleAndRoundedRectangleStrokesAreCSSOutlines() throws {
    let capsule = try #require(shapeSVG(render(Capsule().stroke(Color.green, lineWidth: 2))))
    #expect(capsule.styles["border-radius"] == "9999px")
    #expect(capsule.styles["outline-offset"] == "-1px")
    let border = try #require(shapeSVG(render(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.green, lineWidth: 2))))
    #expect(border.styles["border-radius"] == "12px")
    // strokeBorder centers the line one half-width inside the bounds.
    #expect(border.styles["outline-offset"] == "-2px")
  }

  @Test
  func testCircleFitsShorterSideInNonSquareFrame() throws {
    let tree = FiberTree(Circle().fill(Color.red).frame(width: 200, height: 100), deferLazyCollections: false)
    let svg = try #require(shapeSVG(tree.renderNode))
    #expect(svg.attributes["preserveAspectRatio"] == "xMidYMid meet")
    let d = try #require(elements(named: "path", in: svg).first?.attributes["d"])
    // A 100pt circle centered at x = 100: leftmost point at x = 50.
    #expect(d.contains("50"))
    var path = Path()
    path.addEllipse(in: CGRect(origin: CGPoint(x: 50, y: 0), size: CGSize(width: 100, height: 100)))
    #expect(Circle().path(in: CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 200, height: 100)))._svgPathData == path._svgPathData)
  }

  @Test
  func testBackgroundShapeTakesTheSizeOfTheFrameItDecorates() throws {
    // A background is offered the size of the view it decorates, so a circle behind a 64-point frame is a 64-point
    // circle that CSS paints, not one fitted to whatever size the surrounding layout proposed.
    let layer = try #require(shapeLayer(FiberTree(
      Text("N").frame(width: 64, height: 64).background(Circle().fill(Color.gray.opacity(0.12))),
      deferLazyCollections: false
    ).renderNode))
    #expect(layer.kind == .element("div"))
    #expect(layer.styles["border-radius"] == "9999px")
  }

  @Test
  func testCircleWithoutFrameUsesAspectPreservingNominalBox() throws {
    let svg = try #require(shapeSVG(render(Circle().stroke(Color.red, lineWidth: 3))))
    #expect(svg.attributes["preserveAspectRatio"] == "xMidYMid meet")
    #expect(svg.attributes["data-shape-fit"] == "intrinsic")
    let path = try #require(elements(named: "path", in: svg).first)
    #expect(path.attributes["vector-effect"] == "non-scaling-stroke")
  }

  @Test
  func testShapeShadowFollowsTheShapeNotItsBox() throws {
    let background = render(
      Text("Chip").padding().background(Capsule().fill(Color.red)).shadow(color: .black, radius: 4, x: 0, y: 2)
    )
    var styles: [String: String] = [:]
    background._forEachHost { styles.merge($0.styles) { $1 } }
    #expect(styles["filter"]?.contains("drop-shadow(0px 2px 8px") == true)
    #expect(styles["box-shadow"] == nil)

    let direct = render(Circle().fill(Color.red).shadow(color: .black, radius: 4))
    var directStyles: [String: String] = [:]
    direct._forEachHost { directStyles.merge($0.styles) { $1 } }
    #expect(directStyles["filter"]?.contains("drop-shadow") == true)
    #expect(directStyles["box-shadow"] == nil)
  }

  @Test
  func testRectangleShadowKeepsBoxShadow() {
    let node = render(Rectangle().fill(Color.red).shadow(color: .black, radius: 4))
    var styles: [String: String] = [:]
    node._forEachHost { styles.merge($0.styles) { $1 } }
    #expect(styles["box-shadow"] != nil)
  }

  /// The stroke layers an overlay painted as SVG, wherever they are in the tree.
  private func strokeLayers(in node: _RenderNode) -> [_RenderNode] {
    var found: [_RenderNode] = node.attributes["data-shape-style"] == "stroke" ? [node] : []
    for child in node.children { found += strokeLayers(in: child) }
    return found
  }

  /// A solid stroke that is an overlay's whole content is the base's own box decoration: the base carries the ring
  /// as box shadows (the inner and outer halves of a centered stroke, or the inside line of a `strokeBorder`), with no
  /// overlay wrapper and no SVG.
  @Test
  func testSolidStrokeOverlayIsBoxShadowOnItsBase() {
    let red = Color.red._swiftUIWebCSSValue
    let card = render(
      Text("Card").frame(width: 120, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.red, lineWidth: 1) }
    )
    #expect(!card.classes.contains("overlay-layer"))
    #expect(card.styles["box-shadow"] == "inset 0 0 0 0.5px \(red), 0 0 0 0.5px \(red)")
    #expect(card.styles["border-radius"] == "12px")
    #expect(strokeLayers(in: card).isEmpty)

    let inside = render(
      Text("Chip").frame(width: 120, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.green, lineWidth: 2) }
    )
    #expect(!inside.classes.contains("overlay-layer"))
    #expect(inside.styles["box-shadow"] == "inset 0 0 0 2px \(Color.green._swiftUIWebCSSValue)")
    #expect(inside.styles["border-radius"] == "12px")
    #expect(strokeLayers(in: inside).isEmpty)
  }

  @Test
  func testCapsuleAndRectangleStrokeOverlaysAreBoxShadows() {
    let capsule = render(Text("Pill").frame(width: 120, height: 32).overlay { Capsule().stroke(Color.blue, lineWidth: 1) })
    #expect(!capsule.classes.contains("overlay-layer"))
    #expect(capsule.styles["border-radius"] == "9999px")
    #expect(capsule.styles["box-shadow"]?.hasPrefix("inset 0 0 0 0.5px") == true)

    let rectangle = render(Text("Line").frame(width: 80, height: 20).overlay { Rectangle().stroke(Color.red, lineWidth: 1) })
    #expect(!rectangle.classes.contains("overlay-layer"))
    #expect(rectangle.styles["border-radius"] == nil)
    #expect(rectangle.styles["box-shadow"] != nil)
  }

  /// Anything else keeps the overlay wrapper and the SVG stroke.
  @Test
  func testStrokeOverlaysOutsideTheSolidCaseKeepTheSVG() {
    func keepsSVG<V: View>(_ view: V) -> Bool {
      let node = render(view)
      return node.classes.contains("overlay-layer") && !strokeLayers(in: node).isEmpty
    }
    let dashed = StrokeStyle(lineWidth: 1, dash: [4, 2])
    #expect(keepsSVG(Text("A").frame(width: 120, height: 44).overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.red, style: dashed) }))
    #expect(keepsSVG(Text("B").frame(width: 120, height: 44).overlay { RoundedRectangle(cornerRadius: 12).stroke(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom), lineWidth: 1) }))
    #expect(keepsSVG(Text("C").frame(width: 120, height: 44).overlay(alignment: .topLeading) { RoundedRectangle(cornerRadius: 12).stroke(Color.red, lineWidth: 1) }))
    #expect(keepsSVG(Text("D").frame(width: 44, height: 44).overlay { Circle().stroke(Color.red, lineWidth: 1) }))
    #expect(keepsSVG(Text("E").frame(width: 120, height: 44).overlay { RoundedRectangle(cornerRadius: 12).inset(by: 2).stroke(Color.red, lineWidth: 1) }))
    #expect(keepsSVG(Text("F").frame(width: 120, height: 44).overlay {
      ZStack {
        RoundedRectangle(cornerRadius: 12).stroke(Color.red, lineWidth: 1)
        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.blue, lineWidth: 1)
      }
    }))
    // A fractional line width antialiases differently as a box shadow, so it keeps the SVG.
    #expect(keepsSVG(Text("I").frame(width: 120, height: 44).clipShape(RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.red, lineWidth: 1.5) }))
    // The base's corners must be the stroke's corners, or the stroke would follow the clip's radius.
    #expect(keepsSVG(Text("G").frame(width: 120, height: 44).clipShape(RoundedRectangle(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.red, lineWidth: 1) }))
    // A clipped or faded base would clip or fade the stroke that the overlay draws beside it.
    #expect(keepsSVG(Text("H").frame(width: 120, height: 44).opacity(0.5).overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.red, lineWidth: 1) }))
  }
}
