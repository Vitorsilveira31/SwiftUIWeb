import Foundation
import Testing
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite
@MainActor
struct CoreCanvasAPIContractTests {
  @Test
  func atan2ApproximationPreservesQuadrantsAndVerticalAxes() {
    let pi = Double.pi
    #expect(_swiftUIWebAtan2(1, -1) > pi / 2)
    #expect(_swiftUIWebAtan2(-1, -1) < -pi / 2)
    #expect(_swiftUIWebAtan2(1, 0) == pi / 2)
    #expect(_swiftUIWebAtan2(-1, 0) == -pi / 2)
  }

  @Test
  func graphicsContextRecordsEveryDrawingPrimitiveAndRestoresLayers() throws {
    let gradient = Gradient(colors: [.red, .blue])
    var symbols = GraphicsContext.Symbols()
    symbols.add(Text("text fallback"), id: "text")
    symbols.add(Image("image fallback", alt: "Image fallback"), id: "image")
    symbols.add(Color.red, id: "other")
    symbols.add("replacement", id: "text")
    #expect(symbols["text"] == "replacement")
    #expect(symbols["missing"] == nil)
    symbols["text"] = nil
    #expect(symbols["text"] == nil)

    let canvas = Canvas(renderer: { context, _ in
      #expect(context.opacity == 1)
      #expect(context.blendMode == .normal)
      #expect(context.transform.tx == 0)

      context.opacity = -0.5
      #expect(context.opacity == 0)
      context.opacity = 1.5
      #expect(context.opacity == 1)
      context.blendMode = .multiply
      #expect(context.blendMode == .multiply)
      context.transform = CGAffineTransform(a: 2, b: 0, c: 0, d: 3, tx: 4, ty: 5)
      #expect(context.transform.tx == 4)
      #expect(context.transform.d == 3)

      context.fill(Rectangle(), with: Color.green, style: FillStyle(eoFill: true))
      context.fill(Circle(), with: LinearGradient(
        colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing
      ))
      context.stroke(Rectangle(), with: Color.purple, lineWidth: 2)
      context.stroke(Circle(), with: LinearGradient(
        colors: [.blue, .green], startPoint: .leading, endPoint: .trailing
      ), style: StrokeStyle(lineWidth: 3))
      context.fill(Circle(), with: RadialGradient(
        colors: [.orange, .purple], center: .center, startRadius: 2, endRadius: 12
      ))
      context.fill(Circle(), with: AngularGradient(
        colors: [.green, .blue], center: .center, startAngle: .zero, endAngle: .degrees(180)
      ))
      context.fill(Rectangle(), with: Material.ultraThinMaterial)
      context.fill(Circle(), with: RadialGradient(
        colors: [.orange, .purple], center: .center, startRadius: 2, endRadius: 12
      ))
      context.fill(Circle(), with: AngularGradient(
        colors: [.green, .blue], center: .center, startAngle: .zero, endAngle: .degrees(180)
      ))

      let clip = Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 8))
      context.clip(to: clip, style: FillStyle(eoFill: true))
      context.translateBy(x: 2, y: 3)
      context.scaleBy(x: 2, y: 4)
      context.rotate(by: .degrees(30))
      let transformBeforeLayer = context.transform
      context.drawLayer { layer in
        layer.opacity = 0.25
        layer.blendMode = .screen
        layer.translateBy(x: 100, y: 200)
      }
      #expect(context.transform == transformBeforeLayer)
      #expect(context.opacity == 1)
      #expect(context.blendMode == .multiply)

      let resolvedText = context.resolve(Text("Canvas text"))
      #expect(resolvedText.measure(in: CGSize(width: 0, height: 4)).width == 0)
      #expect(resolvedText.measure(in: CGSize(width: 100, height: 4)).height == 4)
      context.draw(resolvedText, at: CGPoint(x: 5, y: 6), anchor: .topLeading)

      let image = context.resolve(Image("resolved.png"))
      context.draw(image, at: CGPoint(x: 7, y: 8))
      context.draw(image, in: CGRect(x: 1, y: 2, width: 3, height: 4))
      if let symbol = context.resolveSymbol(id: "star") {
        context.draw(symbol, at: CGPoint(x: 9, y: 10), anchor: .bottomTrailing)
      }
      context.withCGContext { nested in
        nested.fill(Rectangle(), with: .color(.orange))
      }
      #expect(context.resolveSymbol(id: "absent") == nil)
    }, symbolProvider: {
      symbols.add("symbol fallback", id: "star")
      return symbols
    })
    let node = FiberTree(canvas).renderNode
    let commands = node._canvasCommands
    #expect(commands.contains { if case .fill(_, .color(Color.green.cssValue), true) = $0 { return true }; return false })
    #expect(commands.contains { if case .stroke(_, .color(Color.purple.cssValue), _) = $0 { return true }; return false })
    #expect(commands.contains { if case .clip(_, true) = $0 { return true }; return false })
    #expect(commands.contains { if case .save = $0 { return true }; return false })
    #expect(commands.contains { if case .restore = $0 { return true }; return false })
    #expect(commands.contains { if case .text("Canvas text", _, _, _, _) = $0 { return true }; return false })
    #expect(commands.contains { if case .image("resolved.png", nil, _, _) = $0 { return true }; return false })
    #expect(commands.contains { if case .image("resolved.png", _, nil, _) = $0 { return true }; return false })
    #expect(commands.contains { if case .symbol(_, "symbol fallback", _, _, _, _) = $0 { return true }; return false })
    #expect(commands.contains { if case .fill(_, .linear, _) = $0 { return true }; return false })
    #expect(commands.contains { if case .stroke(_, .linear, _) = $0 { return true }; return false })
    #expect(commands.contains { if case .fill(_, .radial, _) = $0 { return true }; return false })
    #expect(commands.contains { if case .fill(_, .angular, _) = $0 { return true }; return false })
    #expect(commands.contains {
      if case .fill(_, .color("color-mix(in srgb, Canvas 28%, transparent)"), _) = $0 { return true }
      return false
    })
    #expect(gradient.stops.count == 2)
  }

  @Test
  func canvasSupportsInoutSymbolProvidersAndResolvedBezierMeshColors() throws {
    let canvas = Canvas(renderer: { context, _ in
      if let symbol = context.resolveSymbol(id: "badge") {
        context.draw(symbol, at: CGPoint(x: 4, y: 5))
      }
    }, symbolProvider: { symbols in
      symbols.add(Text("inout fallback"), id: "badge")
    })
    let canvasNode = FiberTree(canvas).renderNode
    #expect(canvasNode._canvasCommands.contains {
      if case .symbol(_, "inout fallback", _, _, _, _) = $0 { return true }
      return false
    })

    let bezier = MeshGradient.BezierPoint(
      position: .init(0.25, 0.75),
      leadingControlPoint: .init(0.1, 0.7),
      topControlPoint: .init(0.2, 0.6),
      trailingControlPoint: .init(0.3, 0.8),
      bottomControlPoint: .init(0.4, 0.9)
    )
    let resolvedColor = Color.Resolved(red: 0.2, green: 0.4, blue: 0.6)
    let mesh = MeshGradient(
      width: 1,
      height: 1,
      bezierPoints: [bezier],
      resolvedColors: [resolvedColor]
    )
    let payload = try #require(FiberTree(mesh).renderNode.attributes["data-mesh-gradient-payload"])
    let decoded = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
    #expect(decoded["bezierPoints"] as? [[String: Any]] != nil)
    #expect((decoded["colors"] as? [String])?.first == resolvedColor.color.cssValue)
  }

  @Test
  func pathBoundsIncludeLinesCurvesArcsAndAllRectangularTransforms() {
    var points = Path()
    points.move(to: CGPoint(x: 2, y: 3))
    points.addLine(to: CGPoint(x: 4, y: 5))
    points.addCurve(
      to: CGPoint(x: 8, y: 9),
      control1: CGPoint(x: -2, y: 1),
      control2: CGPoint(x: 10, y: 12)
    )
    points.addQuadCurve(to: CGPoint(x: 6, y: 4), control: CGPoint(x: 0, y: 14))
    points.addArc(
      center: CGPoint(x: 20, y: 20), radius: -3,
      startAngle: .zero, endAngle: .degrees(90), clockwise: true
    )
    // SwiftUI's bounds: the curves' own extent, not their control points, and the arc's (17...23 both ways).
    let pointBounds = points.boundingRect
    #expect(pointBounds.origin.x == 2)
    #expect(pointBounds.origin.y == 3)
    #expect(pointBounds.size.width == 21)
    #expect(pointBounds.size.height == 20)

    let rectangle = Path(CGRect(x: 1, y: 2, width: 10, height: 8))
    let ellipse = Path(ellipseIn: CGRect(x: 3, y: 4, width: 7, height: 5))
    let rounded = Path(
      roundedRect: CGRect(x: 5, y: 6, width: 20, height: 12),
      cornerRadius: 4,
      style: .continuous
    )
    #expect(Path().isEmpty)
    #expect(rectangle.boundingRect == CGRect(x: 1, y: 2, width: 10, height: 8))
    #expect(ellipse.boundingRect == CGRect(x: 3, y: 4, width: 7, height: 5))
    #expect(rounded.boundingRect == CGRect(x: 5, y: 6, width: 20, height: 12))
    #expect(Path(roundedRect: CGRect(x: 0, y: 0, width: 8, height: 6), cornerSize: CGSize(width: 2, height: 3)).boundingRect.size == CGSize(width: 8, height: 6))

    var transformed = Path()
    transformed.addRect(
      CGRect(x: 1, y: 2, width: 3, height: 4),
      transform: CGAffineTransform(translationX: 10, y: -5)
    )
    transformed.addEllipse(
      in: CGRect(x: 0, y: 0, width: 2, height: 2),
      transform: CGAffineTransform(translationX: -8, y: 6)
    )
    transformed.addRoundedRect(
      in: CGRect(x: 1, y: 1, width: 2, height: 2),
      cornerSize: CGSize(width: 1, height: 1),
      transform: CGAffineTransform(translationX: 30, y: 40)
    )
    let transformedBounds = transformed.boundingRect
    #expect(transformedBounds.origin == CGPoint(x: -8, y: -3))
    #expect(transformedBounds.size == CGSize(width: 41, height: 46))

    var relative = Path()
    relative.addRelativeArc(
      center: CGPoint(x: 4, y: 5), radius: 2,
      startAngle: .zero, delta: .degrees(45)
    )
    relative.addPath(rectangle, transform: CGAffineTransform(translationX: 12, y: 14))
    // The 45° arc runs from (6, 5) to (4 + 2 cos 45°, 5 + 2 sin 45°), as in SwiftUI.
    #expect(abs(relative.boundingRect.minX - 5.414) < 1e-3 && relative.boundingRect.minY == 5)
    #expect(relative.boundingRect.maxX == 23)
    #expect(relative.boundingRect.maxY == 24)
    #expect(rectangle.applying(.identity).boundingRect == rectangle.boundingRect)
    #expect(rectangle.applying(CGAffineTransform(translationX: 2, y: 3)).boundingRect.origin == CGPoint(x: 3, y: 5))
  }

  @Test
  func aFullCircleArcProducesClosedTwoSegmentSvgGeometry() {
    var path = Path()
    path.addArc(
      center: CGPoint(x: 10, y: 20),
      radius: 6,
      startAngle: .zero,
      endAngle: Angle(radians: 2 * Double.pi),
      clockwise: false
    )

    #expect(path.boundingRect == CGRect(x: 4, y: 14, width: 12, height: 12))
    #expect(path._svgPathData.contains("A 6 6 0 1 1"))
    #expect(path._svgPathData.components(separatedBy: "A 6 6").count == 3)

    var partialArc = Path()
    partialArc.addArc(
      center: CGPoint(x: 10, y: 20),
      radius: 6,
      startAngle: .zero,
      endAngle: .degrees(90),
      clockwise: false
    )
    #expect(partialArc._svgPathData.contains("A 6 6 0 0 1"))
  }

  @Test
  func svgPathSerializationPreservesCommandsAndSupportsAffineShapeTransforms() {
    var path = Path()
    path.move(to: CGPoint(x: 1, y: 2))
    path.addLine(to: CGPoint(x: 3, y: 4))
    path.addCurve(
      to: CGPoint(x: 8, y: 9),
      control1: CGPoint(x: 4, y: 5),
      control2: CGPoint(x: 6, y: 7)
    )
    path.addQuadCurve(to: CGPoint(x: 10, y: 11), control: CGPoint(x: 9, y: 12))
    path.addArc(
      center: CGPoint(x: 20, y: 20), radius: 5,
      startAngle: .zero, endAngle: .degrees(90), clockwise: false
    )
    path.addArc(
      center: CGPoint(x: 30, y: 30), radius: 4,
      startAngle: .zero, endAngle: .degrees(360), clockwise: true
    )
    path.addRect(CGRect(x: 2, y: 3, width: 8, height: 6))
    path.addEllipse(in: CGRect(x: 4, y: 5, width: 12, height: 8))
    path.addRoundedRect(
      in: CGRect(x: 1, y: 1, width: 16, height: 10),
      cornerSize: CGSize(width: 3, height: 2)
    )
    let serialized = path._svgPathData
    #expect(serialized.contains("C 4 5 6 7 8 9"))
    #expect(serialized.contains("Q 9 12 10 11"))
    #expect(serialized.contains("A 5 5"))
    #expect(serialized.contains("A 4 4 0 1 0"))
    #expect(serialized.contains("L 10 3"))
    #expect(serialized.contains("Q 17 1"))
    #expect(serialized.hasSuffix("Z"))

    let transform = CGAffineTransform(a: 1, b: 0.2, c: 0.3, d: 1, tx: 11, ty: -7)
    var transformed = Path()
    transformed.addRect(CGRect(x: 1, y: 2, width: 3, height: 4), transform: transform)
    transformed.addEllipse(in: CGRect(x: 2, y: 3, width: 8, height: 6), transform: transform)
    transformed.addRoundedRect(
      in: CGRect(x: 3, y: 4, width: 10, height: 8),
      cornerSize: CGSize(width: 2, height: 3),
      transform: transform
    )
    let transformedSVG = transformed._svgPathData
    #expect(transformedSVG.contains("M 12.6 -4.8"))
    #expect(transformedSVG.contains("L 15.6 -4.2"))
    #expect(transformedSVG.contains("Q"))
    #expect(transformedSVG.contains("Z"))
  }

  @Test
  func pathAddLinesStartsFromItsFirstPointAndContainsFollowsTheFill() {
    var polyline = Path()
    polyline.addLines([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
    // The fill closes the open polyline: a triangle with corners (0, 0), (10, 0) and (10, 10).
    #expect(polyline.contains(CGPoint(x: 9, y: 0.5)))
    #expect(polyline.contains(CGPoint(x: 5, y: 4)))
    #expect(!polyline.contains(CGPoint(x: 2, y: 5)))
    #expect(polyline.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 10))

    var empty = Path()
    empty.addLines([])
    #expect(empty.isEmpty)
    var continued = Path()
    continued.move(to: CGPoint(x: -4, y: 0))
    continued.addLines([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 4)])
    // As in SwiftUI: the lines start a new subpath, so there is no triangle from (-4, 0); the lone move still counts in
    // the bounds.
    #expect(!continued.contains(CGPoint(x: -1, y: 0.5)))
    #expect(continued.boundingRect == CGRect(x: -4, y: 0, width: 4, height: 4))
  }

  @Test
  func pathTangentArcFillletsTheCornerAndDegeneratesToALine() {
    // The corner (10, 0) between (0, 0) and (10, 10), filleted with radius 5: the arc runs from (5, 0) to (10, 5)
    // about the center (5, 5), so the corner cut away is outside the circle.
    var rounded = Path()
    rounded.move(to: CGPoint(x: 0, y: 0))
    rounded.addArc(tangent1End: CGPoint(x: 10, y: 0), tangent2End: CGPoint(x: 10, y: 10), radius: 5)
    rounded.addLine(to: CGPoint(x: 10, y: 10))
    #expect(rounded.contains(CGPoint(x: 8, y: 3)))
    #expect(rounded.contains(CGPoint(x: 7, y: 1)))
    #expect(!rounded.contains(CGPoint(x: 9.5, y: 0.5)))
    #expect(!rounded.contains(CGPoint(x: 2, y: 8)))

    // A zero radius, or collinear tangent points, add only a line to the first tangent point.
    var zeroRadius = Path()
    zeroRadius.move(to: CGPoint(x: 0, y: 0))
    zeroRadius.addArc(tangent1End: CGPoint(x: 10, y: 0), tangent2End: CGPoint(x: 10, y: 10), radius: 0)
    #expect(zeroRadius.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 0))
    var collinear = Path()
    collinear.move(to: CGPoint(x: 0, y: 0))
    collinear.addArc(tangent1End: CGPoint(x: 10, y: 0), tangent2End: CGPoint(x: 20, y: 0), radius: 5)
    #expect(collinear.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 0))

    // Without a current point, or right after a close, SwiftUI starts from the origin and opens a new subpath at the arc:
    // the values are SwiftUI's (bounds (5, 0, 5, 5), and a degenerate arc only moves to the first tangent point).
    func near(_ rect: CGRect, _ expected: CGRect) -> Bool {
      abs(rect.minX - expected.minX) < 1e-6 && abs(rect.minY - expected.minY) < 1e-6
        && abs(rect.width - expected.width) < 1e-6 && abs(rect.height - expected.height) < 1e-6
    }
    var started = Path()
    started.addArc(tangent1End: CGPoint(x: 10, y: 0), tangent2End: CGPoint(x: 10, y: 10), radius: 5)
    #expect(near(started.boundingRect, CGRect(x: 5, y: 0, width: 5, height: 5)))
    var afterClose = Path()
    afterClose.move(to: CGPoint(x: 5, y: 0))
    afterClose.addLine(to: CGPoint(x: 6, y: 3))
    afterClose.closeSubpath()
    afterClose.addArc(tangent1End: CGPoint(x: 10, y: 10), tangent2End: CGPoint(x: 20, y: 10), radius: 2)
    #expect(!afterClose.contains(CGPoint(x: 7.8, y: 5)), "no line from the closed subpath's start to the arc")
    var degenerate = Path()
    degenerate.addArc(tangent1End: CGPoint(x: 10, y: 0), tangent2End: CGPoint(x: 20, y: 0), radius: 5)
    #expect(degenerate.boundingRect == CGRect(x: 10, y: 0, width: 0, height: 0))

    // A transform places the arc: the scaled arc is the plain one with every coordinate doubled.
    var plain = Path()
    plain.move(to: CGPoint(x: 0, y: 0))
    plain.addArc(tangent1End: CGPoint(x: 5, y: 0), tangent2End: CGPoint(x: 5, y: 5), radius: 2.5)
    var scaled = Path()
    scaled.move(to: CGPoint(x: 0, y: 0))
    scaled.addArc(
      tangent1End: CGPoint(x: 2.5, y: 0), tangent2End: CGPoint(x: 2.5, y: 2.5), radius: 1.25,
      transform: CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 0, ty: 0)
    )
    // The scaled arc is the plain arc: its tangent points and radius map to (5, 0), (5, 5) and 2.5.
    #expect(plain.contains(CGPoint(x: 4, y: 1)))
    #expect(scaled.contains(CGPoint(x: 4, y: 1)))
    #expect(!scaled.contains(CGPoint(x: 4.9, y: 0.1)))
  }

  @Test
  func arcBoundsAreTheArcsNotItsCircle() {
    // SwiftUI's values: the bounds of the arc itself, through a transform too.
    func bounds(_ build: (inout Path) -> Void) -> [Double] {
      var path = Path()
      build(&path)
      let rect = path.boundingRect
      return [rect.minX, rect.minY, rect.width, rect.height].map { ($0 * 1_000).rounded() / 1_000 }
    }
    #expect(bounds { $0.addArc(center: .zero, radius: 10, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) } == [0, 0, 10, 10])
    #expect(bounds { $0.addArc(center: .zero, radius: 10, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: true) } == [-10, -10, 20, 20])
    #expect(bounds { $0.addArc(center: CGPoint(x: 5, y: 5), radius: 5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false) } == [0, 0, 10, 5])
    #expect(bounds { $0.addArc(center: .zero, radius: 10, startAngle: .degrees(10), endAngle: .degrees(80), clockwise: false) } == [1.736, 1.736, 8.112, 8.112])
    // Through a rotation the extremes are found in the rotated space; the path keeps its matrix to three decimals.
    let rotated = bounds {
      $0.addArc(center: .zero, radius: 10, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false,
                transform: CGAffineTransform(rotationAngle: Double.pi / 4))
    }
    #expect(zip(rotated, [-7.071, 7.071, 14.142, 2.929]).allSatisfy { abs($0 - $1) < 0.005 }, "\(rotated)")
  }

  @Test
  func pathContainsSupportsBothFillRules() {
    var nested = Path(CGRect(x: 0, y: 0, width: 10, height: 10))
    nested.addRect(CGRect(x: 2, y: 2, width: 6, height: 6))
    // Two subpaths with the same winding overlap at winding 2: nonzero fills it, even-odd leaves a hole.
    #expect(nested.contains(CGPoint(x: 5, y: 5)))
    #expect(!nested.contains(CGPoint(x: 5, y: 5), eoFill: true))
    #expect(nested.contains(CGPoint(x: 1, y: 1), eoFill: true))
    #expect(!nested.contains(CGPoint(x: 11, y: 5)))
  }

  @Test
  func strokedPathOutlinesCapsJoinsAndDashes() {
    var line = Path()
    line.move(to: CGPoint(x: 0, y: 0))
    line.addLine(to: CGPoint(x: 10, y: 0))
    let butt = line.strokedPath(StrokeStyle(lineWidth: 8))
    #expect(butt.contains(CGPoint(x: 5, y: 3)))
    #expect(butt.contains(CGPoint(x: 5, y: -3.5)))
    #expect(!butt.contains(CGPoint(x: 5, y: 5)))
    #expect(!butt.contains(CGPoint(x: -1, y: 0)))

    let square = line.strokedPath(StrokeStyle(lineWidth: 8, lineCap: .square))
    #expect(square.contains(CGPoint(x: -3, y: 3)))
    #expect(!square.contains(CGPoint(x: -5, y: 0)))

    let round = line.strokedPath(StrokeStyle(lineWidth: 8, lineCap: .round))
    #expect(round.contains(CGPoint(x: -2, y: 2)))
    #expect(!round.contains(CGPoint(x: -3, y: 3)))

    // The corner (10, 0) turns from +x to +y. A miter reaches (14, -4); a bevel cuts it off, and so does a miter
    // limit below the miter ratio of 1.41.
    var corner = Path()
    corner.move(to: CGPoint(x: 0, y: 0))
    corner.addLine(to: CGPoint(x: 10, y: 0))
    corner.addLine(to: CGPoint(x: 10, y: 10))
    #expect(corner.strokedPath(StrokeStyle(lineWidth: 8)).contains(CGPoint(x: 13, y: -3)))
    #expect(!corner.strokedPath(StrokeStyle(lineWidth: 8, lineJoin: .bevel)).contains(CGPoint(x: 13, y: -3)))
    #expect(!corner.strokedPath(StrokeStyle(lineWidth: 8, miterLimit: 1)).contains(CGPoint(x: 13, y: -3)))
    #expect(!corner.strokedPath(StrokeStyle(lineWidth: 8, lineJoin: .round)).contains(CGPoint(x: 13, y: -3)))

    // Dashes of 2 with gaps of 2 along the 10-unit line: the pieces cover [0, 2], [4, 6] and [8, 10].
    let dashed = line.strokedPath(StrokeStyle(lineWidth: 2, dash: [2, 2]))
    #expect(dashed.contains(CGPoint(x: 1, y: 0)))
    #expect(!dashed.contains(CGPoint(x: 3, y: 0)))
    #expect(dashed.contains(CGPoint(x: 5, y: 0)))

    #expect(line.strokedPath(StrokeStyle(lineWidth: 0)).isEmpty)

    // An arc whose direction disagrees with the sign of its sweep ends at the requested angle: from 0 to a quarter turn
    // clockwise runs three quarters of the circle the other way round, through the top and the left, to (0, 10).
    var arc = Path()
    arc.addArc(center: .zero, radius: 10, startAngle: .radians(0), endAngle: .radians(Double.pi / 2), clockwise: true)
    let arcStroke = arc.strokedPath(StrokeStyle(lineWidth: 2))
    #expect(arcStroke.contains(CGPoint(x: 0, y: -10)))
    #expect(arcStroke.contains(CGPoint(x: -10, y: 0)))
    #expect(arcStroke.contains(CGPoint(x: -8.09, y: 5.88)), "it ends at the requested angle, (0, 10), arriving from the left")
    #expect(!arcStroke.contains(CGPoint(x: 7.07, y: 7.07)), "and does not take the short way round")

    // A dash that covers the seam of a closed contour keeps the corner there: a dash over the whole square, and a dash that
    // spans the start (on for the last 5 and the first 5 units of the 40-unit perimeter), turn it with the miter.
    var seamSquare = Path()
    seamSquare.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
    let solid = seamSquare.strokedPath(StrokeStyle(lineWidth: 2, dash: [100, 100]))
    #expect(solid.contains(CGPoint(x: -0.5, y: -0.5)), "a dash over the whole contour is the closed contour")
    let spanning = seamSquare.strokedPath(StrokeStyle(lineWidth: 2, dash: [10, 10], dashPhase: 5))
    #expect(spanning.contains(CGPoint(x: -0.5, y: -0.5)), "the dash across the seam is one dash with a joined corner")
    #expect(!spanning.contains(CGPoint(x: 7.5, y: 0)), "and the gaps stay gaps")

    // An odd-length pattern repeats once to alternate on and off, so [5] is dashes of 5 with gaps of 5 and its cycle is 10:
    // started 5 into it, the pieces cover [5, 10] and [15, 20], as the canvas's setLineDash and lineDashOffset draw them.
    var long = Path()
    long.move(to: CGPoint(x: 0, y: 0))
    long.addLine(to: CGPoint(x: 20, y: 0))
    let odd = long.strokedPath(StrokeStyle(lineWidth: 2, dash: [5], dashPhase: 5))
    #expect(!odd.contains(CGPoint(x: 2, y: 0)))
    #expect(odd.contains(CGPoint(x: 7, y: 0)))
    #expect(!odd.contains(CGPoint(x: 12, y: 0)))
    #expect(odd.contains(CGPoint(x: 17, y: 0)))
  }

  @Test
  func graphicsContextRecordsConcatenationBlendModesAndFilters() {
    let canvas = Canvas(renderer: { context, _ in
      context.scaleBy(x: 2, y: 2)
      // The matrix is applied in user space before the scale: the origin goes to (10, 0), then to (20, 0).
      context.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 10, ty: 0))
      #expect(context.transform.a == 2)
      #expect(context.transform.tx == 20)

      #expect(context.blendMode == .normal)
      context.blendMode = .sourceAtop
      #expect(context.blendMode == .sourceAtop)
      context.fill(Rectangle(), with: Color.red)
      context.blendMode = .clear
      context.fill(Rectangle(), with: Color.red)
      context.blendMode = .normal

      context.addFilter(.blur(radius: 10))
      context.addFilter(.shadow(color: .red, radius: 0, x: 3, y: -3))
      context.addFilter(.grayscale(0.5))
      context.fill(Rectangle(), with: Color.blue)
    }, symbolProvider: { GraphicsContext.Symbols() })
    let node = FiberTree(canvas).renderNode
    let commands = node._canvasCommands

    #expect(commands.contains { if case .setTransform(2, 0, 0, 2, 20, 0) = $0 { return true }; return false })
    #expect(commands.contains { if case .blendMode(.sourceAtop) = $0 { return true }; return false })
    #expect(commands.contains { if case .blendMode(.clear) = $0 { return true }; return false })
    // The host reads the mode from the wire: clear is its own operation, drawn opaque with destination-out.
    #expect(node.attributes["data-canvas-commands"]?.contains("{\"o\":\"b\",\"v\":\"clear\"}") == true)
    let filters = commands.compactMap { command -> String? in
      if case .filter(let css) = command { return css }
      return nil
    }
    #expect(filters.count == 3)
    #expect(filters.first == "blur(10px)")
    #expect(filters.last == "blur(10px) drop-shadow(3px -3px 0px \(Color.red.cssValue)) grayscale(0.5)")
    // The blend mode and filters are canvas state: the last fill after the filters sees all three.
    let fills = commands.filter { if case .fill = $0 { return true }; return false }
    #expect(fills.count == 3)

    // The CoreGraphics raw values, and the canvas operators the host sets for them.
    #expect(GraphicsContext.BlendMode.normal.rawValue == 0)
    #expect(GraphicsContext.BlendMode.destinationOut.rawValue == 23)
    #expect(GraphicsContext.BlendMode.plusLighter.rawValue == 27)
    #expect(GraphicsContext.BlendMode.clear.rawValue == 16)
  }

  @Test
  func viewBlendModesAndColorInvertRenderTheirFilterAndAttributes() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Text("Inverted").colorInvert().grayscale(0.2)
        Text("Cut out").blendMode(.destinationOut)
        Text("Atop").blendMode(.sourceAtop)
        Text("Lighter").blendMode(.plusLighter)
      }
    )
    #expect(html.contains("data-color-invert=\"true\""))
    #expect(html.contains("filter: invert(1) grayscale(0.2)"))
    // CSS has no operator for the Porter-Duff modes on an element: the attribute keeps the name, the style is normal.
    #expect(html.contains("data-blend-mode=\"destinationOut\""))
    #expect(html.contains("data-blend-mode=\"sourceAtop\""))
    #expect(html.contains("mix-blend-mode: plus-lighter"))
  }
}
