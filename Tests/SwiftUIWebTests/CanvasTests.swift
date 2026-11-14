import Dispatch
import Testing
import Foundation
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
final class CanvasTests {
  private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
      Path { path in
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
      }
    }
  }

  /// As in SwiftUI, a copy of a context draws into the same canvas with a state of its own, and the original keeps its
  /// state: what each draws is preceded by its own opacity and transform.
  @Test
  func aCopyOfTheContextDrawsWithItsOwnState() {
    let canvas = Canvas { context, size in
      context.translateBy(x: 10, y: 0)
      for index in 0..<2 {
        var copy = context
        copy.opacity = 0.5
        copy.translateBy(x: Double(index), y: 0)
        copy.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)), with: .color(.red))
      }
      context.fill(Path(CGRect(x: 0, y: 0, width: 2, height: 2)), with: .color(.blue))
    }.frame(width: 20, height: 20)
    let commands = FiberTree(canvas).renderNode._canvasCommands.map { command -> String in
      switch command {
      case .translate(let x, _): return "t\(Int(x))"
      case .opacity(let value): return "a\(value)"
      case .fill: return "f"
      case .resetState: return "rs"
      case .setTransform(_, _, _, _, let tx, _): return "m\(Int(tx))"
      default: return "?"
      }
    }
    #expect(commands == ["t10", "a0.5", "t0", "f", "rs", "m10", "a0.5", "t1", "f", "rs", "m10", "f"])
  }

  @Test
  func testCanvasRecordsPathsPaintAndTransforms() {
    let canvas = Canvas { context, size in
      var path = Path()
      path.move(to: CGPoint(x: 0, y: 0))
      path.addLine(to: CGPoint(x: size.width, y: size.height))
      context.fill(path, with: .color(.blue), style: FillStyle(eoFill: true))
      context.stroke(path, with: .red, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .bevel, dash: [4, 2], dashPhase: 1))
      context.translateBy(x: 4, y: 5)
      context.scaleBy(x: 2, y: 1.5)
      context.rotate(by: .degrees(12))
    }.frame(width: 200, height: 100)

    let node = FiberTree(canvas).renderNode
    _expectEqual(node.kind, .element("canvas"))
    _expectEqual(node.attributes["data-canvas-size"], "200,100")
    _expectEqual(node._canvasCommands.count, 5)
    _expectNotNil(node._canvasFingerprint)
    if case .fill(let path, let shading, let eoFill) = node._canvasCommands[0] {
      _expectEqual(path.count, 2)
      _expectTrue(eoFill)
      if case .color(let value) = shading { _expectEqual(value, Color.blue.cssValue) }
      else { _fail("expected color shading") }
    } else { _fail("expected fill command") }
  }

  @Test
  func testPaletteAndHierarchicalLevelsPaintThroughConcreteShadings() {
    let canvas = Canvas { context, _ in
      var path = Path()
      path.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
      context.fill(path, with: .palette([.color(.red), .color(.blue), .color(.green)]))
      context.fill(path, with: .palette([]))
      context.fill(path, with: .foreground)
      context.fill(path, with: .style(.secondary))
      context.stroke(path, with: .palette([.style(.tertiary), .color(.blue)]), lineWidth: 1)
    }.frame(width: 100, height: 100)

    let node = FiberTree(canvas).renderNode
    let shadings: [String] = node._canvasCommands.compactMap { command in
      switch command {
      case .fill(_, .color(let value), _), .stroke(_, .color(let value), _): return value
      default: return nil
      }
    }
    _expectEqual(shadings.count, 5, "every palette and level resolves to a concrete color")
    _expectEqual(shadings[0], Color.red.cssValue, "a palette paints with its first entry")
    _expectEqual(shadings[1], "transparent", "an empty palette paints nothing")
    _expectEqual(shadings[2], "currentColor", ".foreground is level 0")
    _expectEqual(shadings[3], HierarchicalShapeStyle.secondary._swiftUIWebCSSValue, ".secondary is level 1")
    _expectEqual(shadings[4], HierarchicalShapeStyle.tertiary._swiftUIWebCSSValue, "a palette entry keeps its own level")
  }

  @Test
  func testShadingStyleGradientsResolveUnitPointsAgainstThePaintedPathBounds() {
    let canvas = Canvas { context, _ in
      var path = Path()
      path.addRect(CGRect(x: 10, y: 20, width: 100, height: 50))
      context.fill(path, with: .style(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)))
      context.fill(path, with: .style(RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 10)))
    }.frame(width: 200, height: 100)

    let node = FiberTree(canvas).renderNode
    guard case .fill(_, .linear(_, let start, let end), _) = node._canvasCommands[0] else { return _fail("expected a linear gradient") }
    _expectEqual(start, CGPoint(x: 10, y: 45), "leading is the left edge of the path, at its vertical middle")
    _expectEqual(end, CGPoint(x: 110, y: 45), "trailing is the right edge of the path")
    guard case .fill(_, .radial(_, let center, _, _, _), _) = node._canvasCommands[1] else { return _fail("expected a radial gradient") }
    _expectEqual(center, CGPoint(x: 60, y: 45), ".center is the middle of the path")
  }

  @Test
  func testRepeatedAndMirroredLinearGradientsExpandToPaddedPeriods() {
    let ramp = Gradient(colors: [.black, .white])
    let canvas = Canvas { context, _ in
      var path = Path()
      path.addRect(CGRect(x: 0, y: 0, width: 100, height: 10))
      context.fill(path, with: .linearGradient(ramp, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 40, y: 0), options: [.repeat]))
      context.fill(path, with: .linearGradient(ramp, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 40, y: 0), options: [.mirror]))
      context.fill(path, with: .linearGradient(ramp, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 40, y: 0)))
    }.frame(width: 100, height: 10)

    let node = FiberTree(canvas).renderNode
    // The bounds reach ramp coordinate 2.5, so repeat covers three periods
    // (0...3) and mirror covers two mirrored periods (0...4).
    guard case .fill(_, .linear(let repeated, let repeatStart, let repeatEnd), _) = node._canvasCommands[0],
          case .fill(_, .linear(let mirrored, _, let mirrorEnd), _) = node._canvasCommands[1],
          case .fill(_, .linear(let padded, _, _), _) = node._canvasCommands[2] else {
      return _fail("expected linear gradient fills")
    }
    _expectEqual(repeated.count, 6)
    _expectEqual(repeatStart.x, 0)
    _expectEqual(repeatEnd.x, 120)
    _expectEqual(mirrored.count, 8)
    _expectEqual(mirrorEnd.x, 160)
    _expectEqual(padded.count, 2)
    // Offsets stay in ramp order across periods, so the seam between two periods
    // is a sharp step for repeat and a fold for mirror.
    _expectTrue(abs(repeated[2].location - 1.0 / 3.0) < 1e-9)
    _expectTrue(abs(repeated[3].location - 2.0 / 3.0) < 1e-9)
    _expectTrue(abs(mirrored[3].location - 0.5) < 1e-9)
    _expectTrue(abs(mirrored[7].location - 1.0) < 1e-9)
  }

  @Test
  func testTiledImageShadingRecordsSourceOriginAndScale() {
    let tile = Image("tile.png")
    let canvas = Canvas { context, _ in
      var path = Path()
      path.addRect(CGRect(x: 0, y: 0, width: 80, height: 40))
      context.fill(path, with: .tiledImage(tile, origin: CGPoint(x: 5, y: 7), scale: 10))
    }.frame(width: 80, height: 40)

    let node = FiberTree(canvas).renderNode
    guard case .fill(_, .tiled(let source, let origin, let sourceRect, let scale), _) = node._canvasCommands[0] else {
      return _fail("expected a tiled image fill")
    }
    _expectEqual(source, "tile.png")
    _expectEqual(origin.x, 5)
    _expectEqual(origin.y, 7)
    _expectEqual(sourceRect.width, 1)
    _expectEqual(scale, 10)
  }

  @Test
  func testCanvasSupportsGradientClipOpacityBlendTextImageAndCustomShape() {
    let canvas = Canvas { context, _ in
      let gradient = Gradient(stops: [
        .init(color: .blue, location: 0),
        .init(color: .purple, location: 0.5),
        .init(color: .red, location: 1)
      ])
      let shape = Triangle()
      context.fill(shape, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 160, y: 90)))
      var clip = Path()
      clip.addRect(CGRect(x: 0, y: 0, width: 80, height: 80))
      context.clip(to: clip)
      context.opacity = 0.4
      context.blendMode = .multiply
      context.draw(Text("Hello"), at: CGPoint(x: 10, y: 12), anchor: .topLeading)
      context.draw(Image("photo.png"), in: CGRect(x: 10, y: 20, width: 40, height: 30))
    }.frame(width: 160, height: 90)

    let node = FiberTree(canvas).renderNode
    _expectEqual(node._canvasCommands.count, 6)
    _expectTrue(node._canvasCommands.contains { if case .clip = $0 { return true }; return false })
    _expectTrue(node._canvasCommands.contains { if case .opacity = $0 { return true }; return false })
    _expectTrue(node._canvasCommands.contains { if case .blendMode(.multiply) = $0 { return true }; return false })
    _expectTrue(node._canvasCommands.contains { if case .text("Hello", _, _, _, _) = $0 { return true }; return false })
    _expectTrue(node._canvasCommands.contains { if case .image("photo.png", _, _, _) = $0 { return true }; return false })
    guard case .fill(_, .linear(let stops, _, _), _) = node._canvasCommands[0] else {
      return _fail("expected linear gradient fill")
    }
    _expectEqual(stops.count, 3)
  }

  @Test
  func testCanvasRecordsRoundedGeometryNestedLayersAndImagePlacement() {
    let canvas = Canvas { context, _ in
      var rounded = Path()
      rounded.addRoundedRect(
        in: CGRect(x: 8, y: 10, width: 90, height: 40),
        cornerSize: CGSize(width: 10, height: 8),
        transform: CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 4, ty: 2)
      )
      let gradient = Gradient(colors: [.blue, .green])
      context.drawLayer { layer in
        layer.opacity = 0.5
        layer.fill(rounded, with: .radialGradient(
          gradient,
          center: CGPoint(x: 0.5, y: 0.5),
          startRadius: 2,
          endRadius: 80
        ))
      }
      context.fill(Circle(), with: .angularGradient(
        gradient,
        center: CGPoint(x: 0.5, y: 0.5),
        startAngle: .zero,
        endAngle: .degrees(180)
      ))
      context.draw(Image("photo.png"), at: CGPoint(x: 100, y: 40), anchor: .bottomTrailing)
    }.frame(width: 140, height: 80)

    let node = FiberTree(canvas).renderNode
    _expectEqual(node._canvasCommands.count, 6)
    guard case .fill(let roundedPath, .radial(_, _, _, _, _), _) = node._canvasCommands[2] else {
      return _fail("expected rounded radial fill inside layer")
    }
    _expectTrue(roundedPath.first?.hasPrefix("RRT") == true)
    guard case .fill(_, .angular(_, _, _, _), _) = node._canvasCommands[4] else {
      return _fail("expected angular gradient fill")
    }
    guard case .image(let source, nil, let point?, .bottomTrailing) = node._canvasCommands[5] else {
      return _fail("expected positioned image command")
    }
    _expectEqual(source, "photo.png")
    _expectEqual(point.x, 100)
    _expectEqual(point.y, 40)
  }

  @Test
  func testCanvasResolvesShapeStyleGradientUnitPointsAgainstCanvasSize() {
    let canvas = Canvas { context, _ in
      context.fill(
        Rectangle(),
        with: LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
      )
    }.frame(width: 120, height: 60)

    let node = FiberTree(canvas).renderNode
    guard case .fill(_, .linear(_, let start, let end), _) = node._canvasCommands[0] else {
      return _fail("expected ShapeStyle linear gradient")
    }
    _expectEqual(start.x, 0)
    _expectEqual(start.y, 0)
    _expectEqual(end.x, 120)
    _expectEqual(end.y, 60)
  }

  @Test
  func testGraphicsContextCopiesRetainValueSemantics() {
    // As in SwiftUI, the copy draws into the same canvas; its state stays its own.
    let canvas = Canvas { context, _ in
      var copy = context
      copy.opacity = 0.5
      copy.fill(Rectangle(), with: .red)
      context.fill(Circle(), with: .blue)
    }
    let node = FiberTree(canvas).renderNode
    _expectEqual(node._canvasCommands.count, 4)
    guard case .fill(_, .color(Color.red.cssValue), _) = node._canvasCommands[1],
          case .resetState = node._canvasCommands[2],
          case .fill(_, .color(Color.blue.cssValue), _) = node._canvasCommands[3] else {
      return _fail("mutating a copied GraphicsContext should not alter the original")
    }
  }

  @Test
  func testCanvasSymbolsResolveAndRemainInCommandStream() {
    let canvas = Canvas(renderer: { context, _ in
      if let symbol = context.resolveSymbol(id: 7) {
        context.draw(symbol, at: CGPoint(x: 20, y: 20))
      }
    }, symbols: {
      Text("badge").tag(7)
    })
    let node = FiberTree(canvas).renderNode
    guard case .symbol(_, "badge", _, _, _, _) = node._canvasCommands.first else {
      return _fail("expected resolved symbol")
    }
  }

  @Test
  func testCanvasAcceptsTaggedViewBuilderSymbols() {
    let canvas = Canvas(renderer: { context, _ in
      if let symbol = context.resolveSymbol(id: 8) {
        context.draw(symbol, at: CGPoint(x: 12, y: 12))
      }
    }, symbols: {
      Text("builder-symbol").tag(8)
    })
    let node = FiberTree(canvas).renderNode
    guard case .symbol(_, "builder-symbol", _, _, _, _) = node._canvasCommands.first else {
      return _fail("expected tagged builder symbol")
    }
  }

  @Test
  func testCanvasUsesIntrinsicFallbackAndStableIdentityMetadata() {
    let first = Canvas { context, _ in context.fill(Rectangle(), with: .green) }
    let second = Canvas { context, _ in context.fill(Rectangle(), with: .green) }
    let firstNode = FiberTree(first).renderNode
    let secondNode = FiberTree(second).renderNode
    _expectEqual(firstNode.attributes["data-canvas-size"], "300,150")
    _expectEqual(firstNode._canvasFingerprint, secondNode._canvasFingerprint)
    _expectEqual(firstNode.attributes["data-draw-canvas"], "true")
    let html = StaticHTMLFiberRenderer().render(first)
    _expectTrue(html.contains("<canvas"))
    _expectTrue(html.contains("data-canvas-color-mode=\"nonLinear\""))
  }

  @Test
  func testCanvasTracksRootProposalForResponsiveSizing() {
    let canvas = Canvas { _, _ in }
    let initial = FiberTree(canvas, deferLazyCollections: false, rootLayoutProposal: ProposedViewSize(width: 640, height: 360)).renderNode
    _expectEqual(initial.attributes["data-canvas-size"], "640,360")
    _expectEqual(initial.styles["width"], "640px")
    _expectEqual(initial.styles["height"], "360px")
  }

  @Test
  func testResolvedSymbolsCarryTheirMarkupAndDeclaredFrame() {
    let canvas = Canvas(renderer: { context, _ in
      if let symbol = context.resolveSymbol(id: 3) {
        _expectEqual(symbol.size, CGSize(width: 20, height: 10))
        context.draw(symbol, at: CGPoint(x: 1, y: 2))
      }
      if let escaped = context.resolveSymbol(id: 4) {
        _expectEqual(escaped.size, CGSize(width: 0, height: 0))
        context.draw(escaped, in: CGRect(x: 0, y: 0, width: 30, height: 30))
      }
    }, symbols: {
      Text("framed").frame(width: 20, height: 10).tag(3)
      Text("a<b & \"c\"").tag(4)
    })
    let node = FiberTree(canvas).renderNode
    let wire = node.attributes["data-canvas-commands"] ?? ""
    _expectTrue(wire.contains("\"o\":\"sym\""))
    _expectTrue(wire.contains("a&lt;b &amp; &quot;c&quot;"))
    guard case .symbol(let markup, "framed", _, _, _, _) = node._canvasCommands.first else {
      return _fail("expected the framed symbol first")
    }
    _expectTrue(markup.contains("framed"))
    _expectTrue(markup.contains("width:20px"))
    _expectEqual(node._canvasCommands.count, 2)
    if case .symbol(_, _, let point, let anchor, _, _) = node._canvasCommands[1] {
      _expectEqual(point, CGPoint(x: 15, y: 15))
      _expectTrue(anchor == UnitPoint.center)
    } else {
      _fail("expected the in-rect symbol to be centred")
    }
  }

  @Test
  func testResolvedSystemImagesPaintWithTheirShading() {
    let canvas = Canvas { context, _ in
      var glyph = context.resolve(Image(systemName: "star"))
      _expectEqual(glyph.size, CGSize(width: 17, height: 17))
      _expectEqual(glyph.baseline, 17)
      glyph.shading = .palette([.color(.red), .color(.blue)])
      context.draw(glyph, at: CGPoint(x: 0, y: 0), anchor: .topLeading)

      var plain = context.resolve(Image("photo.png"))
      _expectEqual(plain.size, CGSize(width: 0, height: 0))
      plain.shading = nil
      context.draw(plain, at: CGPoint(x: 0, y: 0), anchor: .topLeading)

      var text = context.resolve(Text("Shaded"))
      text.shading = .color(.green)
      context.draw(text, at: CGPoint(x: 0, y: 0), anchor: .topLeading)
      context.draw(context.resolve(Text("Foreground")), at: CGPoint(x: 0, y: 0), anchor: .topLeading)
    }
    let commands = FiberTree(canvas).renderNode._canvasCommands
    _expectTrue(commands.contains {
      if case .symbol(_, _, _, _, _, let color) = $0 { return color == Color.red.cssValue }
      return false
    })
    _expectTrue(commands.contains {
      if case .image("photo.png", nil, _, _) = $0 { return true }
      return false
    })
    _expectTrue(commands.contains {
      if case .text("Shaded", _, _, .color(Color.green.cssValue), _) = $0 { return true }
      return false
    })
    _expectTrue(commands.contains {
      if case .text("Foreground", _, _, .color(_), _) = $0 { return true }
      return false
    })
  }

  @Test
  func testForegroundLevelsInACanvasResolveToTheEnclosingForegroundStyles() {
    let canvas = Canvas { context, _ in
      let band = Path(CGRect(x: 0, y: 0, width: 10, height: 10))
      context.fill(band, with: .style(HierarchicalShapeStyle.secondary))
      context.fill(band, with: .style(HierarchicalShapeStyle.tertiary))
      context.fill(band, with: .style(HierarchicalShapeStyle.quaternary))
    }
    .foregroundStyle(Color.red, Color.blue, Color.green)
    let commands = FiberTree(canvas).renderNode._canvasCommands
    _expectTrue(commands.contains { if case .fill(_, .color(Color.blue.cssValue), _) = $0 { return true }; return false })
    _expectTrue(commands.contains { if case .fill(_, .color(Color.green.cssValue), _) = $0 { return true }; return false })
    // Quaternary is not one of the three styles `foregroundStyle` sets, so it keeps its color mix.
    _expectTrue(commands.contains { if case .fill(_, .color(HierarchicalShapeStyle.quaternary._swiftUIWebCSSValue), _) = $0 { return true }; return false })
  }

  @Test
  func testHierarchicalTextReadsTheForegroundPaintVariables() {
    let view = VStack { Text("b").foregroundStyle(.secondary) }.foregroundStyle(Color.red, Color.blue)
    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("color: var(--secondary-style, color-mix(in srgb, currentColor 60%, transparent))"))
  }

  @Test
  func testResolvedTextReportsIntrinsicMeasurement() {
    let canvas = Canvas { context, _ in
      let resolved = context.resolve(Text("1234"))
      _expectGreaterThan(resolved.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width, 0)
      _expectGreaterThan(resolved.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).height, 0)
    }
    _ = FiberTree(canvas).renderNode
  }

  @Test
  func testCanvasRendererReadsReactiveStateAndUpdatesFingerprint() {
    struct ReactiveCanvas: View {
      @State var enabled = false
      var body: some View {
        VStack {
          Button("Toggle") { enabled.toggle() }
          Canvas { context, _ in
            context.draw(Text(enabled ? "enabled" : "disabled"), at: CGPoint(x: 4, y: 4), anchor: .topLeading)
          }
        }
      }
    }
    let fixture = ReactiveCanvas()
    let tree = FiberTree(fixture)
    let before = tree.renderNode.htmlDescription
    tree.dispatch(event: "click")
    _ = tree.update(fixture)
    let after = tree.renderNode.htmlDescription
    _expectNotEqual(before, after)
  }

  @Test
  func testCanvasCommandRecordingBenchmarkMatrix() {
    for count in [100, 1_000, 10_000] {
      let start = DispatchTime.now().uptimeNanoseconds
      let node = FiberTree(Canvas { context, _ in
        var path = Path()
        for index in 0..<count {
          let x = Double(index % 320)
          let y = Double((index * 17) % 120)
          if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
          else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 1))
      }).renderNode
      let elapsed = DispatchTime.now().uptimeNanoseconds - start
      print("canvas-recording,commands=\(count),elapsedNs=\(elapsed),fingerprintBytes=\(node.attributes["data-canvas-fingerprint"]?.utf8.count ?? 0)")
      _expectEqual(node._canvasCommands.count, 1)
      _expectLessThan(node.attributes["data-canvas-fingerprint"]?.utf8.count ?? 0, 64)
    }
  }

  @Test
  func testCanvasPublishesItsDrawingAndAsksTheHostForItsSize() {
    let canvas = Canvas { context, _ in
      context.fill(Path(CGRect(x: 0, y: 0, width: 10, height: 5)), with: .color(.red))
      context.translateBy(x: 2, y: 3)
      context.draw(Text("hi"), at: CGPoint(x: 1, y: 1))
    }.frame(width: 20, height: 10)

    let node = FiberTree(canvas).renderNode
    let wire = node.attributes["data-canvas-commands"] ?? ""
    _expectTrue(wire.hasPrefix("[{\"o\":\"f\",\"d\":\"M 0 0"), "the fill carries its path as SVG data: \(wire)")
    _expectTrue(wire.contains("{\"o\":\"t\",\"x\":2,\"y\":3}"))
    _expectTrue(wire.contains("\"o\":\"tx\",\"t\":\"hi\""))
    // The drawing closure receives the laid-out size, so the host measures the canvas as it does a GeometryReader.
    _expectEqual(node.attributes["data-geometry-reader"], "true")
    _expectNotNil(node.events["geometry"])
  }
}
