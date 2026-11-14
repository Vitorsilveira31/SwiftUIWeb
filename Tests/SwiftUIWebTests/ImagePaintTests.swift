import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
final class ImagePaintTests {
  private let tilePNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGP4z8DAAMIM/4EAAB/uBfsL2WiLAAAAAElFTkSuQmCC"

  @Test
  func testImagePaintKeepsSwiftUIDefaultsAndStaticConstructor() {
    let paint = ImagePaint(image: Image("tile.png"))
    _expectEqual(paint.sourceRect, CGRect(x: 0, y: 0, width: 1, height: 1))
    _expectEqual(paint.scale, 1)
    let styled: ImagePaint = .image(Image("tile.png"), sourceRect: CGRect(x: 0.25, y: 0, width: 0.5, height: 1), scale: 4)
    _expectEqual(styled.sourceRect.origin.x, 0.25)
    _expectEqual(styled.scale, 4)
    _expectEqual(styled.image.source, "tile.png")
  }

  @Test
  func testImagePaintBackgroundIsSizedByTheBrowserFromItsMarkers() {
    let html = StaticHTMLFiberRenderer().render(
      Text("Tiled").padding(12).background(.image(Image(tilePNG), scale: 10))
    )
    _expectTrue(html.contains("background: url(&quot;\(tilePNG)&quot;)"))
    _expectTrue(html.contains("data-image-paint=\"true\""))
    _expectTrue(html.contains("data-image-paint-source=\"\(tilePNG)\""))
    _expectTrue(html.contains("data-image-paint-rect=\"0,0,1,1\""))
    _expectTrue(html.contains("data-image-paint-scale=\"10\""))
    _expectFalse(html.contains("background-color"))
  }

  @Test
  func testImagePaintShapeFillIsAnSVGPatternOfTheImage() {
    let html = StaticHTMLFiberRenderer().render(
      Circle().fill(ImagePaint(image: Image(tilePNG), sourceRect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), scale: 2)).frame(width: 60, height: 60)
    )
    _expectTrue(html.contains("<pattern"))
    _expectTrue(html.contains("patternUnits=\"userSpaceOnUse\""))
    _expectTrue(html.contains("<image"))
    _expectTrue(html.contains("href=\"\(tilePNG)\""))
    _expectTrue(html.contains("data-image-paint-rect=\"0,0,0.5,0.5\""))
    _expectTrue(html.contains("data-image-paint-scale=\"2\""))
    _expectTrue(html.contains("url(#paint-gradient-"))
  }

  @Test
  func testImagePaintRectangleFillPaintsOnlyThroughThePattern() {
    let html = StaticHTMLFiberRenderer().render(
      Rectangle().fill(ImagePaint(image: Image(tilePNG))).frame(width: 40, height: 40)
    )
    _expectTrue(html.contains("<pattern"))
    _expectFalse(html.contains("background: url("))
  }

  @Test
  func testImagePaintForegroundStyleClipsTheImageToText() {
    let html = StaticHTMLFiberRenderer().render(
      Text("Image").foregroundStyle(.image(Image(tilePNG), scale: 3))
    )
    _expectTrue(html.contains("background-image: url(&quot;\(tilePNG)&quot;)"))
    _expectTrue(html.contains("background-clip: text"))
    _expectTrue(html.contains("data-image-paint-scale=\"3\""))
  }

  @Test
  func testErasedImagePaintKeepsItsTileGeometry() {
    let erased = AnyShapeStyle(ImagePaint(image: Image(tilePNG), scale: 5))
    let html = StaticHTMLFiberRenderer().render(Text("Erased").background(erased))
    _expectTrue(html.contains("data-image-paint-scale=\"5\""))
    _expectTrue(html.contains("background: url(&quot;\(tilePNG)&quot;)"))
  }

  /// A source that closes the quoted `url("…")` string and then appends declarations.
  // No ":" before a "/", so it reads as a file path of the app (a name with a scheme loads nothing at all); the quote
  // must still not end the URL.
  private let breakoutSource = "x.png\"); position fixed; inset 0; z-index 9; background url(\"y"

  /// The text after the single `url("…")` token that opens `value`, or nil when a quote inside it is not escaped.
  private func _textAfterQuotedURL(_ value: String) -> String? {
    let scalars = Array(value.unicodeScalars)
    guard scalars.starts(with: "url(\"".unicodeScalars) else { return nil }
    var index = 5
    while index < scalars.count {
      switch scalars[index] {
      case "\\":
        index += 2
      case "\"":
        guard index + 1 < scalars.count, scalars[index + 1] == ")" else { return nil }
        var rest = ""
        rest.unicodeScalars.append(contentsOf: scalars[(index + 2)...])
        return rest
      case "\n", "\r":
        return nil
      default:
        index += 1
      }
    }
    return nil
  }

  private func _allNodes(_ node: _RenderNode) -> [_RenderNode] {
    [node] + node.children.flatMap { _allNodes($0) }
  }

  @Test
  func testHostileImageSourceCannotEndTheURLStringOrAddDeclarations() {
    let paint = ImagePaint(image: Image(breakoutSource))._swiftUIWebCSSValue
    _expectEqual(_textAfterQuotedURL(paint), "", "the paint is one url token: \(paint)")
    let root = FiberTree(Text("Tiled").padding(12).background(.image(Image(breakoutSource))), deferLazyCollections: false).renderNode
    let painted = _allNodes(root).compactMap { $0.styles["background"] }
    _expectTrue(painted.contains(paint))
    _expectTrue(painted.allSatisfy { _textAfterQuotedURL($0) == "" })
  }

  @Test
  func testHostileTextForegroundImageCannotAddDeclarations() {
    let root = FiberTree(Text("Image").foregroundStyle(.image(Image(breakoutSource))), deferLazyCollections: false).renderNode
    let painted = _allNodes(root).compactMap { $0.styles["background-image"] }
    _expectTrue(!painted.isEmpty)
    _expectTrue(painted.allSatisfy { _textAfterQuotedURL($0) == "" })
  }

  @Test
  func testHostileCustomSymbolMaskCannotAddDeclarations() {
    // No ":" before a "/", so it reads as a file path of the app (one with a scheme loads nothing), and the quote must
    // not end the URL.
    let source = "x.symbol.svg\"); inset 0; z-index 9; mask url(\"y.symbol.svg"
    let root = FiberTree(Image(source), deferLazyCollections: false).renderNode
    let masks = _allNodes(root).compactMap { $0.styles["mask"] }
    _expectEqual(masks.count, 1)
    _expectEqual(masks.first.flatMap(_textAfterQuotedURL), " center / contain no-repeat")
  }

  @Test
  func testLegitimateImageSourcesKeepTheirBytes() {
    // Apple's Image(_:) names an asset or a file of the app, never a remote URL (Image(_:alt:) takes one).
    _expectEqual(ImagePaint(image: Image("https://cdn.example.test/a.png"))._swiftUIWebCSSValue, "none")
    _expectEqual(ImagePaint(image: Image("https://cdn.example.test/a.png", alt: "a"))._swiftUIWebCSSValue, "url(\"https://cdn.example.test/a.png\")")
    _expectEqual(ImagePaint(image: Image(tilePNG))._swiftUIWebCSSValue, "url(\"\(tilePNG)\")")
    _expectEqual(ImagePaint(image: Image("media/cover photo (1).png"))._swiftUIWebCSSValue, "url(\"media/cover photo (1).png\")")
    let mask = FiberTree(Image("icons/star.symbol.svg"), deferLazyCollections: false).renderNode
    _expectTrue(_allNodes(mask).contains { $0.styles["mask"]?.contains("icons/star.symbol.svg") == true })
  }

  @Test
  func testHashedCustomSymbolFileIsStillASymbol() {
    // The release step names a compiled symbol `name.symbol.<hash>.svg`; it must keep drawing as a tinted mask at the
    // text's size, not as a picture at the SVG's own size.
    for file in ["catalog-assets/donut.symbol.svg", "catalog-assets/donut.symbol.ca09577a.svg"] {
      _expectTrue(_isCustomSymbolFile(file))
      let root = FiberTree(Image(file), deferLazyCollections: false).renderNode
      _expectTrue(_allNodes(root).contains { $0.classes.contains("custom-symbol") })
    }
    for file in ["catalog-assets/logo.svg", "catalog-assets/logo.ca09577a.svg", "symbol.svg", "a.symbol.png"] {
      _expectTrue(!_isCustomSymbolFile(file))
    }
  }

  @Test
  func testAnyGradientShapeStylesMatchTheWrappedGradient() {
    let gradient = Gradient(colors: [.red, .blue])
    let wrapped = AnyGradient(gradient)
    _expectEqual(wrapped, AnyGradient(gradient))
    _expectEqual(gradient.colorSpace(.perceptual), AnyGradient(gradient, colorSpace: .perceptual))
    _expectEqual(wrapped.colorSpace(.perceptual).space, .perceptual)
    let linear: LinearGradient = .linearGradient(wrapped, startPoint: .leading, endPoint: .trailing)
    _expectEqual(linear._swiftUIWebCSSValue, LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)._swiftUIWebCSSValue)
    let radial: RadialGradient = .radialGradient(wrapped, center: .center, startRadius: 0, endRadius: 40)
    _expectEqual(radial._swiftUIWebCSSValue, RadialGradient(gradient: gradient, center: .center, startRadius: 0, endRadius: 40)._swiftUIWebCSSValue)
    let conic: AngularGradient = .conicGradient(wrapped, center: .center)
    _expectEqual(conic._swiftUIWebCSSValue, AngularGradient(gradient: gradient, center: .center)._swiftUIWebCSSValue)
  }

  @Test
  func testAnyGradientCanvasShadingsRecordTheSameRampAsGradientShadings() {
    let gradient = Gradient(colors: [.black, .white])
    let canvas = Canvas { context, _ in
      var path = Path()
      path.addRect(CGRect(x: 0, y: 0, width: 100, height: 10))
      context.fill(path, with: .linearGradient(AnyGradient(gradient), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 40, y: 0), options: [.repeat]))
      context.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 40, y: 0), options: [.repeat]))
      context.fill(path, with: .radialGradient(AnyGradient(gradient), center: CGPoint(x: 50, y: 5), startRadius: 0, endRadius: 10))
      context.fill(path, with: .radialGradient(gradient, center: CGPoint(x: 50, y: 5), startRadius: 0, endRadius: 10))
      context.fill(path, with: .radialGradient(AnyGradient(gradient), startCenter: CGPoint(x: 50, y: 5), startRadius: 0, endCenter: CGPoint(x: 60, y: 5), endRadius: 10))
      context.fill(path, with: .radialGradient(gradient, startCenter: CGPoint(x: 50, y: 5), startRadius: 0, endCenter: CGPoint(x: 60, y: 5), endRadius: 10))
      context.fill(path, with: .conicGradient(AnyGradient(gradient), center: CGPoint(x: 50, y: 5)))
      context.fill(path, with: .conicGradient(gradient, center: CGPoint(x: 50, y: 5)))
    }
    let commands = FiberTree(canvas).renderNode._canvasCommands
    _expectEqual(commands.count, 8)
    for pair in [(0, 1), (2, 3), (4, 5), (6, 7)] {
      _expectEqual(String(describing: commands[pair.0]), String(describing: commands[pair.1]))
    }
  }

  @Test
  func testEllipticalGradientDefaultsAndOverloadsMatchTheWrappedGradient() {
    let gradient = Gradient(colors: [.red, .blue])
    let direct = EllipticalGradient(gradient: gradient)
    _expectEqual(direct.startRadiusFraction, 0)
    _expectEqual(direct.endRadiusFraction, 0.5)
    _expectEqual(direct.center, .center)
    _expectEqual(EllipticalGradient(colors: [.red, .blue]), direct)
    _expectEqual(EllipticalGradient(stops: gradient.stops), direct)
    let styled: EllipticalGradient = .ellipticalGradient(AnyGradient(gradient), center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
    _expectEqual(styled, direct)
    let viaStatic: EllipticalGradient = .ellipticalGradient(gradient)
    _expectEqual(viaStatic, direct)
  }

  @Test
  func testEllipticalGradientCSSUsesPercentRadiiAndMapsStartFractionOntoStops() {
    let css = EllipticalGradient(gradient: Gradient(colors: [.black, .white]), startRadiusFraction: 0.25, endRadiusFraction: 0.5)._swiftUIWebCSSValue
    // Radii are percentages of the box (0.5 of the bounds = 50%). The start radius (0.25) lands at 50% of the ray
    // ending at 0.5; stops before it pad with the first color.
    _expectTrue(css.hasPrefix("radial-gradient(ellipse 50% 50% at 50% 50%, "))
    _expectTrue(css.contains(", \(Color.black.cssValue) 0%, "))
    _expectTrue(css.contains("\(Color.black.cssValue) 0%"))
    _expectTrue(css.contains("\(Color.white.cssValue) 100%)"))
    let centered = EllipticalGradient(gradient: Gradient(colors: [.black, .white]), center: .topLeading)._swiftUIWebCSSValue
    _expectTrue(centered.hasPrefix("radial-gradient(ellipse 50% 50% at 0% 0%, "))
  }

  @Test
  func testEllipticalGradientShapeFillIsObjectBoundingBoxRadialGradient() {
    let html = StaticHTMLFiberRenderer().render(
      Rectangle().fill(EllipticalGradient(colors: [.black, .white], center: .center, startRadiusFraction: 0.1, endRadiusFraction: 0.5)).frame(width: 120, height: 60)
    )
    _expectTrue(html.contains("<radialGradient"))
    _expectTrue(html.contains("cx=\"50%\""))
    _expectTrue(html.contains("cy=\"50%\""))
    _expectTrue(html.contains("r=\"0.5\""))
    _expectTrue(html.contains("fr=\"0.1\""))
    _expectFalse(html.contains("gradientUnits"))
  }
}
