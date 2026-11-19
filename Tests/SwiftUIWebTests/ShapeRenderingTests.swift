import Testing
import Foundation
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
import SwiftUIWebHTML
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite
@MainActor
final class ShapeRenderingTests {
  // `strokeBorder` is declared on `InsettableShape` only, as in SwiftUI.
  private struct Triangle: InsettableShape {
    func path(in rect: CGRect) -> Path {
      var path = Path()
      path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.closeSubpath()
      return path
    }

    func inset(by amount: CGFloat) -> Triangle { self }
  }

  @Test
  func testFlexibleSolidOutlinesKeepPointSizedCornersAndStroke() {
    let renderer = StaticHTMLFiberRenderer()
    let rounded = renderer.render(Text("Card").overlay {
      RoundedRectangle(cornerRadius: 16).stroke(Color.red, lineWidth: 1)
    })
    #expect(rounded.contains("border-radius: 16px"))
    #expect(rounded.contains("outline: 1px solid \(Color.red.cssValue)"))
    #expect(rounded.contains("outline-offset: -0.5px"))
    let capsule = renderer.render(Text("Filter").overlay { Capsule().stroke(Color.blue, lineWidth: 2) })
    #expect(capsule.contains("border-radius: 9999px"))
    #expect(capsule.contains("outline: 2px solid \(Color.blue.cssValue)"))
    #expect(capsule.contains("outline-offset: -1px"))
    let dashed = renderer.render(RoundedRectangle(cornerRadius: 16).stroke(Color.red, style: StrokeStyle(dash: [2, 4])))
    #expect(!dashed.contains("outline:"))
    #expect(dashed.contains("stroke-dasharray=\"2 4\""))
  }

  @Test
  func testCustomShapeUsesSVGPathGeometry() {
    let html = StaticHTMLFiberRenderer().render(
      Triangle().fill(Color.red).frame(width: 80, height: 60)
    )
    _expectTrue(html.contains("<svg"))
    _expectTrue(html.contains("<path"))
    _expectTrue(html.contains("data-shape=\"shape\""))
    _expectTrue(html.contains("data-shape-style=\"fill\""))
    _expectTrue(html.contains("fill: \(Color.red.cssValue)"))
    _expectFalse(html.contains("fill=\"red\""))
    _expectTrue(html.contains("viewBox=\"0 0 80 60\""))
  }

  @Test
  func testStrokeBorderAndTrimExposeSVGPaintSemantics() {
    let html = StaticHTMLFiberRenderer().render(
      RoundedRectangle(cornerRadius: 12)
        .trim(from: 0.2, to: 0.8)
        .strokeBorder(Color.blue, lineWidth: 4)
        .frame(width: 120, height: 40)
    )
    _expectTrue(html.contains("data-shape-stroke-border=\"true\""))
    _expectTrue(html.contains("stroke-width=\"4\""))
    _expectTrue(html.contains("data-trim-from=\"0.2\""))
    _expectTrue(html.contains("data-trim-to=\"0.8\""))
    _expectTrue(html.contains("pathLength=\"1\""))
    _expectTrue(html.contains("stroke-dasharray="))
  }

  @Test
  func testLinearAndRadialGradientsUseLocalSVGDefinitions() {
    let linear = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
    let radial = RadialGradient(colors: [.white, .black], center: .center, startRadius: 0, endRadius: 40)
    let html = StaticHTMLFiberRenderer().render(
      VStack { linear.frame(width: 40, height: 20); Circle().fill(radial).frame(width: 40, height: 40) }
    )
    _expectTrue(html.contains("<linearGradient"))
    _expectTrue(html.contains("<radialGradient"))
    _expectTrue(html.contains("stop-color: \(Color.red.cssValue)"))
    _expectTrue(html.contains("fill: url(#paint-gradient-"))
  }

  @Test
  func testAngularGradientUsesSVGWedgesClippedToShape() {
    let html = StaticHTMLFiberRenderer().render(
      Circle().fill(AngularGradient(colors: [.red, .blue, .green], center: .center)).frame(width: 80, height: 80)
    )
    _expectTrue(html.contains("data-angular-gradient="))
    _expectTrue(html.contains("<clipPath"))
    _expectTrue(html.contains("data-angular-span="))
  }

  @Test
  func testPathSerializerPreservesTransformsAndArcs() {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addArc(center: CGPoint(x: 20, y: 20), radius: 20, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
    let transformed = path.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 5, ty: 2))
    _expectTrue(transformed._svgPathData.contains("M 5 2"))
    _expectTrue(path._svgPathData.contains("A 20 20"))
  }

  @Test
  func testPathConvenienceInitializersAndBounds() {
    let rect = CGRect(origin: .zero, size: CGSize(width: 24, height: 12))
    let path = Path(roundedRect: rect, cornerRadius: 3)
    _expectFalse(path.isEmpty)
    _expectEqual(path.boundingRect.size.width, 24, accuracy: 0.001)
    _expectEqual(path.boundingRect.size.height, 12, accuracy: 0.001)
    _expectTrue(Path(ellipseIn: rect)._svgPathData.contains("A 12 6"))
    _expectEqual(Rectangle().path(in: rect).boundingRect.size.width, 24, accuracy: 0.001)
  }

  @Test
  func testPathSerializerFormatsFractionalRoundedCoordinatesWithoutFloatingPointDescription() {
    let path = Path(roundedRect: CGRect(x: 0.25, y: 0.5, width: 12.75, height: 6.5), cornerRadius: 2.25)
    let svg = path._svgPathData
    _expectTrue(svg.contains("M 2.5 0.5"))
    _expectTrue(svg.contains("Q 13 0.5 13 2.75"))
    _expectTrue(_pathNumber(-0.5) == "-0.5")
    _expectTrue(_pathNumber(1.25) == "1.25")
  }

  @Test
  func testBuiltInShapePathsRespectInsetsAndContainerGeometry() {
    let rect = CGRect(x: 10, y: 20, width: 80, height: 40)
    let expectedInsetBounds = CGRect(x: 15, y: 25, width: 70, height: 30)

    let rectangle = Rectangle().inset(by: 5).path(in: rect).boundingRect
    _expectEqual(rectangle, expectedInsetBounds)
    // A circle fits the shorter side and is centered, never an ellipse.
    let circle = Circle().inset(by: 5).path(in: rect).boundingRect
    _expectEqual(circle, CGRect(x: 35, y: 25, width: 30, height: 30))
    let ellipse = Ellipse().inset(by: 5).path(in: rect).boundingRect
    _expectEqual(ellipse, expectedInsetBounds)

    let capsule = Capsule(style: .continuous).inset(by: 5).path(in: rect)
    _expectEqual(capsule.boundingRect, expectedInsetBounds)
    _expectFalse(capsule._svgPathData.isEmpty)
    let rounded = RoundedRectangle.rect(cornerRadius: 12, style: .continuous)
      .inset(by: 5)
      .path(in: rect)
    _expectEqual(rounded.boundingRect, expectedInsetBounds)
    _expectFalse(rounded._svgPathData.isEmpty)

    let negativeInset = Rectangle().inset(by: -4).path(in: rect).boundingRect
    _expectEqual(negativeInset, CGRect(x: 10, y: 20, width: 80, height: 40))
    let container = ContainerRelativeShape().path(in: rect).boundingRect
    _expectEqual(container, CGRect(x: 10, y: 20, width: 80, height: 40))

    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Circle().inset(by: 3).fill(Color.blue).frame(width: 40, height: 30)
        RoundedRectangle(cornerRadius: 10).inset(by: 2).strokeBorder(Color.red, lineWidth: 4)
          .frame(width: 40, height: 20)
        Triangle().strokeBorder(lineWidth: 3)
        ContainerRelativeShape().fill(Color.green)
        Text("Shape-style foreground").foregroundStyle(Color.purple)
      }
    )
    #expect(html.contains("data-shape=\"circle\""))
    #expect(html.contains("<path"))
    #expect(html.contains("data-shape-stroke-border=\"true\""))
    #expect(html.contains("data-shape=\"container-relative\""))
    #expect(html.contains("color: \(Color.purple.cssValue)"))
  }

  @Test
  func testAddPathTransformDoesNotLeakIntoFollowingSubpaths() {
    var source = Path()
    source.addRect(CGRect(x: 0, y: 0, width: 4, height: 4))
    var combined = Path()
    combined.addPath(source, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 10, ty: 0))
    combined.addRect(CGRect(x: 0, y: 0, width: 2, height: 2))
    _expectEqual(combined.boundingRect.minX, 0, accuracy: 0.001)
    _expectEqual(combined.boundingRect.maxX, 14, accuracy: 0.001)
  }

  @Test
  func testClipAndMaskRetainCustomShapeGeometry() {
    let clipped = Text("masked")
      .clipShape(Triangle())
      .mask { Triangle() }
    let html = StaticHTMLFiberRenderer().render(clipped)
    _expectTrue(html.contains("data-clip-path="))
    _expectTrue(html.contains("data-mask=\"true\""))
    _expectTrue(html.contains("data-mask-backend=\"svg\""))
    _expectTrue(html.contains("mask-image:"))
  }

  @Test
  func testGradientMaskFadesByItsAlpha() {
    let faded = Text("faded").mask {
      LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
    }
    let html = StaticHTMLFiberRenderer().render(faded)
    _expectTrue(html.contains("data-mask=\"true\""))
    // The gradient is the mask, not a rectangle path, and it is not drawn over the content.
    _expectTrue(html.contains("mask-image: linear-gradient("))
    _expectFalse(html.contains("mask-image: url("))
    _expectTrue(html.contains("data-mask-backend=\"gradient\""))
  }

  @Test
  func testBareShapeIsFilledWithTheForegroundStyle() {
    let bare = StaticHTMLFiberRenderer().render(Triangle().frame(width: 14, height: 18))
    _expectTrue(bare.contains("fill: currentColor"))
    let painted = StaticHTMLFiberRenderer().render(Triangle().stroke(Color.red, lineWidth: 2).frame(width: 14, height: 18))
    _expectFalse(painted.contains("fill: currentColor"))
  }

  @Test
  func testStrokeWithoutAStyleTakesTheForegroundStyle() {
    // `stroke(style:)` and `stroke(lineWidth:)` outline the shape in the foreground style, as in SwiftUI.
    let html = StaticHTMLFiberRenderer().render(Circle().stroke(lineWidth: 2).foregroundStyle(Color.red).frame(width: 10, height: 10))
    _expectTrue(html.contains("stroke: currentColor"))
    _expectFalse(html.contains("CanvasText"))
  }

  @Test
  func testShapeStyleErasureAndViewTransformsRemainInspectable() {
    let style = AnyShapeStyle(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
    let html = StaticHTMLFiberRenderer().render(
      Circle().fill(style).transformEffect(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 4, ty: 6))
    )
    _expectTrue(html.contains("data-shape-paint=\"linear-gradient"))
    _expectTrue(html.contains("matrix(1, 0, 0, 1, 4, 6)"))
    _expectTrue(html.contains("<linearGradient"))
  }

  @Test
  func testFillStyleControlsEvenOddRuleAndAntialiasing() {
    let html = StaticHTMLFiberRenderer().render(
      Path { path in
        path.addRect(CGRect(origin: .zero, size: CGSize(width: 20, height: 20)))
      }.fill(Color.black, style: FillStyle(eoFill: true, antialiased: false))
    )
    _expectTrue(html.contains("fill-rule=\"evenodd\""))
    _expectTrue(html.contains("shape-rendering=\"crispEdges\""))
  }

  @Test
  func testDefaultPaintAndStrokeStyleOverloadsKeepTheirSVGContracts() {
    let style = StrokeStyle(
      lineWidth: 3,
      lineCap: .round,
      lineJoin: .bevel,
      miterLimit: 4,
      dash: [2, 4],
      dashPhase: 1
    )
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Circle().fill()
        Ellipse().stroke(Color.blue, style: style)
        Capsule().stroke(lineWidth: 2)
        Triangle().strokeBorder(Color.green, style: style)
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color.primary, style: style)
        Rectangle().strokeBorder(lineWidth: 2)
      }
    )

    #expect(html.contains("data-shape=\"circle\""))
    #expect(html.contains("data-shape-paint=\"CanvasText\""))
    #expect(html.contains("stroke-linecap=\"round\""))
    #expect(html.contains("stroke-linejoin=\"bevel\""))
    #expect(html.contains("stroke-miterlimit=\"4\""))
    #expect(html.contains("stroke-dasharray=\"2 4\""))
    #expect(html.contains("stroke-dashoffset=\"1\""))
    #expect(html.contains("data-shape-stroke-border=\"true\""))
    #expect(html.contains("data-shape=\"rounded-rectangle-8\""))
  }
}
