import Testing
@testable import SwiftUIWeb
@testable @_spi(Renderer) import SwiftUIWebCore
@testable @_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

private enum StageSpace: Hashable { case stage }

/// Host payload helpers: the window frame followed by ancestor spaces,
/// nearest first (see GeometryMeasurement.swift for the wire format).
private func payload(_ frame: String, _ spaces: [(kind: String, name: String, frame: String)] = []) -> String {
  spaces.reduce(frame) { $0 + "\u{1E}\($1.kind)\u{1F}\($1.name)\u{1F}\($1.frame)" }
}

private func describe(_ rect: CGRect) -> String {
  "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.size.width)),\(Int(rect.size.height))"
}

private func describe(_ rect: CGRect?) -> String { rect.map(describe) ?? "nil" }

private func attribute(_ name: String, in node: _RenderNode) -> String? {
  if let value = node.attributes[name] { return value }
  for child in node.children { if let value = attribute(name, in: child) { return value } }
  return nil
}

private struct SizeOnlyReaderHost: View {
  nonisolated(unsafe) static var renders = 0
  var body: some View {
    VStack {
      GeometryReader { proxy in
        let _ = SizeOnlyReaderHost.renders += 1
        Text("w=\(Int(proxy.size.width))")
      }
    }
  }
}

@Suite
@MainActor
final class GeometryCoordinateSpaceTests {
  @Test
  func proxyResolvesEveryCoordinateSpaceFromHostRects() throws {
    let view = GeometryReader { proxy in
      VStack {
        Text("local=" + describe(proxy.frame(in: .local)))
        Text("global=" + describe(proxy.frame(in: .global)))
        Text("named=" + describe(proxy.frame(in: .named("stage"))))
        Text("typed=" + describe(proxy.frame(in: NamedCoordinateSpace.named("stage"))))
        Text("scroll=" + describe(proxy.frame(in: .scrollView)))
        Text("vertical=" + describe(proxy.frame(in: .scrollView(axis: .vertical))))
        Text("horizontal=" + describe(proxy.frame(in: .scrollView(axis: .horizontal))))
        Text("missing=" + describe(proxy.frame(in: .named("missing"))))
        Text("bounds=" + describe(proxy.bounds(of: .named("stage"))))
        Text("missingBounds=" + describe(proxy.bounds(of: .named("missing"))))
        Text("size=\(Int(proxy.size.width))x\(Int(proxy.size.height))")
      }
    }
    let tree = FiberTree(view)
    let reader = try #require(tree.findNode(withEvent: "geometry"))
    tree.dispatch(event: "geometry", value: payload("100,250,80,40", [
      ("n", "stage", "20,50,300,500"),
      ("s", "vertical", "10,30,320,400"),
      ("n", "stage", "0,0,999,999")
    ]), on: reader)
    _ = tree.update(view)
    let html = tree.renderNode.htmlDescription
    for expected in [
      "local=0,0,80,40", "global=100,250,80,40", "named=80,200,80,40", "typed=80,200,80,40",
      "scroll=90,220,80,40", "vertical=90,220,80,40", "horizontal=100,250,80,40",
      "missing=100,250,80,40", "bounds=-80,-200,300,500", "missingBounds=nil", "size=80x40"
    ] {
      #expect(html.contains(expected), "\(expected) missing from \(html)")
    }
  }

  // Under a 2x scale the page measures in window pixels and adds the size the view lays out at: the proxy is in the view's points.
  @Test
  func aScaleAboveTheViewIsDividedOutOfTheProxy() throws {
    let view = GeometryReader { proxy in
      VStack {
        Text("local=" + describe(proxy.frame(in: .local)))
        Text("global=" + describe(proxy.frame(in: .global)))
        Text("named=" + describe(proxy.frame(in: .named("stage"))))
        Text("bounds=" + describe(proxy.bounds(of: .named("stage"))))
        Text("size=\(Int(proxy.size.width))x\(Int(proxy.size.height))")
      }
    }
    let tree = FiberTree(view)
    let reader = try #require(tree.findNode(withEvent: "geometry"))
    // A 100x20 view at (200, 40) in the window under a 2x scale, in a 2x named space of 300x500 points at (20, 10).
    tree.dispatch(event: "geometry", value: payload("200,40,200,40,100,20", [("n", "stage", "20,10,600,1000,300,500")]), on: reader)
    _ = tree.update(view)
    let html = tree.renderNode.htmlDescription
    for expected in ["local=0,0,100,20", "global=200,40,200,40", "named=90,15,100,20", "bounds=-90,-15,300,500", "size=100x20"] {
      #expect(html.contains(expected), "\(expected) missing from \(html)")
    }
    // The measurement hands anchors the view where it is in the window, with its size in its own points and its scale.
    let measurement = try #require(_GeometryMeasurement(decoding: "200,40,200,40,100,20"))
    #expect(measurement.anchorFrame.size == CGSize(width: 100, height: 20))
    #expect(measurement.anchorSpace == _AnchorSpace(origin: CGPoint(x: 200, y: 40), scaleX: 2, scaleY: 2))
    // An anchor of that view read by a view under the same scale is in their shared points; read by an unscaled view
    // outside the scale, it is where the view shows in the window; read under another scale, in that reader's points.
    let scaled = _AnchorFrame(space: measurement.anchorSpace, size: measurement.size)
    let bounds = Anchor<CGRect>.Source.bounds._make(scaled)
    #expect(bounds._value(in: _AnchorSpace(origin: CGPoint(x: 100, y: 20), scaleX: 2, scaleY: 2)) == CGRect(x: 50, y: 10, width: 100, height: 20))
    #expect(bounds._value(in: _AnchorSpace(origin: .zero)) == CGRect(x: 200, y: 40, width: 200, height: 40))
    #expect(bounds._value(in: _AnchorSpace(origin: .zero, scaleX: 4, scaleY: 4)) == CGRect(x: 50, y: 10, width: 50, height: 10))
    #expect(Anchor<CGPoint>.Source.center._make(scaled)._value(in: _AnchorSpace(origin: .zero)) == CGPoint(x: 300, y: 60))
    #expect(Anchor<CGPoint>.Source.point(CGPoint(x: 10, y: 5))._make(scaled)._value(in: _AnchorSpace(origin: .zero)) == CGPoint(x: 220, y: 50))
    #expect(Anchor<CGRect>.Source.rect(CGRect(x: 10, y: 5, width: 20, height: 4))._make(scaled)._value(in: _AnchorSpace(origin: .zero)) == CGRect(x: 220, y: 50, width: 40, height: 8))
    // Under a rotation the box's sides are not the view's: the page says where its axes go, which gives the scale used.
    let turned = try #require(_GeometryMeasurement(decoding: "180,40,20,100,100,20,0,1,-1,0\u{1E}n\u{1F}stage\u{1F}0,0,200,400,400,200,0,1,-1,0"))
    #expect(turned.scaleX == 1 && turned.scaleY == 1)
    #expect(turned.size == CGSize(width: 100, height: 20))
    // The view and the stage are turned together (the stage is 400 by 200 points, shown 200 by 400): in the stage's points
    // the view is its plain 100 by 20 frame, 40 along and 0 down from the stage's corner (which shows at the top right).
    #expect(turned.frame(in: .named("stage")) == CGRect(x: 40, y: 0, width: 100, height: 20))
    #expect(turned.bounds(of: .named("stage")) == CGRect(x: -40, y: 0, width: 400, height: 200))
    // A turned view in a stage that is not: its frame there is the turned box.
    let turnedAlone = try #require(_GeometryMeasurement(decoding: "180,40,20,100,100,20,0,1,-1,0\u{1E}n\u{1F}stage\u{1F}100,10,400,300"))
    #expect(turnedAlone.frame(in: .named("stage")) == CGRect(x: 80, y: 30, width: 20, height: 100))
    // Its own corner is the box's top-right one, and its anchors reach a reader outside the rotation turned: the bounds of
    // the 100x20 view are the 20x100 box it shows, and its trailing edge's middle is at the box's bottom.
    #expect(turned.anchorSpace.origin == CGPoint(x: 200, y: 40))
    let window = _AnchorSpace(origin: .zero)
    #expect(Anchor<CGRect>.Source.bounds._make(turned.anchorFrame)._value(in: window) == CGRect(x: 180, y: 40, width: 20, height: 100))
    #expect(Anchor<CGPoint>.Source.trailing._make(turned.anchorFrame)._value(in: window) == CGPoint(x: 190, y: 140))
    // Read by a view under the same rotation, they are in the points the two share.
    #expect(Anchor<CGRect>.Source.bounds._make(turned.anchorFrame)._value(in: turned.anchorSpace) == CGRect(x: 0, y: 0, width: 100, height: 20))
    // A view in a scroll view turned with it: its frame in the scroll view's space is its plain frame there.
    let scrolled = try #require(_GeometryMeasurement(decoding: "370,330,20,50,50,20,0,1,-1,0\u{1E}s\u{1F}vertical\u{1F}300,300,100,200,200,100,0,1,-1,0"))
    #expect(scrolled.frame(in: .scrollView(horizontal: false, vertical: false)) == CGRect(x: 30, y: 10, width: 50, height: 20))
    // A square turned a quarter has the box it would have anyway: its axes still place its corner, at the box's top right.
    let square = try #require(_GeometryMeasurement(decoding: "100,100,40,40,40,40,0,1,-1,0"))
    #expect(Anchor<CGPoint>.Source.topLeading._make(square.anchorFrame)._value(in: window) == CGPoint(x: 140, y: 100))
    // A mirrored view's corner is the box's right edge.
    let mirrored = try #require(_GeometryMeasurement(decoding: "200,40,100,20,100,20,-1,0,0,1"))
    #expect(mirrored.anchorSpace.origin == CGPoint(x: 300, y: 40))
    #expect(Anchor<CGPoint>.Source.topLeading._make(mirrored.anchorFrame)._value(in: window) == CGPoint(x: 300, y: 40))
    // Without a scale nothing changes.
    let plain = try #require(_GeometryMeasurement(decoding: "200,40,100,20"))
    #expect(plain.anchorFrame == _AnchorFrame(space: _AnchorSpace(origin: CGPoint(x: 200, y: 40)), size: CGSize(width: 100, height: 20)))
    #expect(plain.size == CGSize(width: 100, height: 20))
  }

  @Test
  func hashableNamesAndTypedModifierShareOneCoordinateSpaceKey() throws {
    let modified = FiberTree(Text("Stage").coordinateSpace(name: StageSpace.stage))
    let key = try #require(attribute("data-coordinate-space", in: modified.renderNode))
    let typed = FiberTree(Text("Stage").coordinateSpace(.named(StageSpace.stage)))
    #expect(attribute("data-coordinate-space", in: typed.renderNode) == key)
    #expect(FiberTree(Text("Plain").coordinateSpace(.named("plain"))).renderNode.htmlDescription.contains("data-coordinate-space=\"plain\""))
    // The generic spelling and the typed spelling of a String name share one key.
    #expect(attribute("data-coordinate-space", in: FiberTree(Text("Plain").coordinateSpace(name: "plain")).renderNode) == "plain")
    // `.scrollView` is provided by ScrollView itself and is never registered.
    #expect(attribute("data-coordinate-space", in: FiberTree(Text("S").coordinateSpace(.scrollView)).renderNode) == nil)

    let view = GeometryReader { proxy in
      Text("enum=" + describe(proxy.frame(in: .named(StageSpace.stage))))
      Text("case=" + describe(proxy.frame(in: CoordinateSpace.named(StageSpace.stage))))
    }
    let tree = FiberTree(view)
    let reader = try #require(tree.findNode(withEvent: "geometry"))
    tree.dispatch(event: "geometry", value: payload("30,40,10,10", [("n", key, "10,10,100,100")]), on: reader)
    _ = tree.update(view)
    #expect(tree.renderNode.htmlDescription.contains("enum=20,30,10,10"))
    #expect(tree.renderNode.htmlDescription.contains("case=20,30,10,10"))
  }

  @Test
  func coordinateSpaceOnAGroupNamesEachChild() {
    let tree = FiberTree(Group { Text("A"); Text("B") }.coordinateSpace(name: "grouped"))
    let html = tree.renderNode.htmlDescription
    #expect(html.components(separatedBy: "data-coordinate-space=\"grouped\"").count == 3, "\(html)")
  }

  @Test
  func readerTracksPositionOnlyWhenContentReadsAFrame() throws {
    let sizeOnly = SizeOnlyReaderHost()
    let sizeTree = FiberTree(sizeOnly)
    #expect(!sizeTree.renderNode.htmlDescription.contains("data-geometry-position"))
    let sizeNode = try #require(sizeTree.findNode(withEvent: "geometry"))
    let rendersBeforeMeasurement = SizeOnlyReaderHost.renders
    sizeTree.dispatch(event: "geometry", value: "0,0,50,20", on: sizeNode)
    #expect(sizeTree.renderNode.htmlDescription.contains("w=50"))
    let rendersAfterMeasurement = SizeOnlyReaderHost.renders
    #expect(rendersAfterMeasurement > rendersBeforeMeasurement)
    // Scrolling only moves the reader: no visible change, no re-render.
    sizeTree.dispatch(event: "geometry", value: "0,-120,50,20", on: sizeNode)
    #expect(sizeTree.renderNode.htmlDescription.contains("w=50"))
    #expect(SizeOnlyReaderHost.renders == rendersAfterMeasurement)
    sizeTree.dispatch(event: "geometry", value: "0,-120,60,20", on: sizeNode)
    #expect(sizeTree.renderNode.htmlDescription.contains("w=60"))

    let positional = GeometryReader { proxy in
      Text("y=\(Int(proxy.frame(in: .named("scroll")).minY))")
    }
    let tree = FiberTree(positional)
    #expect(tree.renderNode.htmlDescription.contains("data-geometry-position=\"true\""))
    let node = try #require(tree.findNode(withEvent: "geometry"))
    for (offset, expected) in [(0, "y=40"), (25, "y=15"), (60, "y=-20")] {
      tree.dispatch(event: "geometry", value: payload("0,\(140 - offset),50,20", [("n", "scroll", "0,100,300,200")]), on: node)
      _ = tree.update(positional)
      #expect(tree.renderNode.htmlDescription.contains(expected), "\(expected) after scrolling \(offset)")
    }
  }

  @Test
  func onGeometryChangeFiresInitiallyThenOnlyForChangedValues() throws {
    var heights: [Double] = []
    var pairs: [[Double]] = []
    let view = Text("Measured")
      .onGeometryChange(for: Double.self, of: { $0.size.height }) { heights.append($0) }
      .onGeometryChange(for: Double.self) { proxy in
        proxy.frame(in: .named("list")).minY
      } action: { old, new in
        pairs.append([old, new])
      }
    let tree = FiberTree(view)
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("data-geometry-change=\"2\""))
    #expect(html.contains("data-geometry-change-position=\"true\""))
    let node = try #require(tree.findNode(withEvent: "geometryChange"))
    let list = ("n", "list", "0,100,320,480")
    tree.dispatch(event: "geometryChange", value: payload("0,130,320,44", [list]), on: node)
    tree.dispatch(event: "geometryChange", value: payload("0,130,320,44", [list]), on: node)
    tree.dispatch(event: "geometryChange", value: payload("0,110,320,44", [list]), on: node)
    tree.dispatch(event: "geometryChange", value: payload("0,110,320,60", [list]), on: node)
    tree.dispatch(event: "geometryChange", value: "malformed", on: node)
    #expect(heights == [44, 60])
    #expect(pairs == [[30, 30], [30, 10]])
  }

  @Test
  func sizeOnlyGeometryChangeDoesNotRequestScrollTracking() {
    let tree = FiberTree(Text("Size").onGeometryChange(for: CGSize.self, of: { $0.size }) { _ in })
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("data-geometry-change=\"1\""))
    #expect(!html.contains("data-geometry-change-position"))
  }

  @Test
  func readerAndGeometryChangeOnOneViewKeepSeparateEvents() throws {
    var widths: [Double] = []
    let view = GeometryReader { proxy in Text("reader=\(Int(proxy.size.width))") }
      .onGeometryChange(for: Double.self, of: { $0.size.width }) { widths.append($0) }
    let tree = FiberTree(view)
    let node = try #require(tree.findNode(withEvent: "geometryChange"))
    #expect(node.events["geometry"] != nil)
    tree.dispatch(event: "geometry", value: "0,0,64,10", on: node)
    tree.dispatch(event: "geometryChange", value: "0,0,64,10", on: node)
    _ = tree.update(view)
    #expect(widths == [64])
    #expect(tree.renderNode.htmlDescription.contains("reader=64"))
  }

  @Test
  func geometryChangeOnAGroupObservesEachChildIndependently() {
    var values: [Double] = []
    let tree = FiberTree(Group { Text("A"); Text("B") }.onGeometryChange(for: Double.self, of: { $0.size.width }) { values.append($0) })
    func collect(_ node: _RenderNode) -> [_RenderNode] {
      (node.events["geometryChange"] == nil ? [] : [node]) + node.children.flatMap(collect)
    }
    let nodes = collect(tree.renderNode)
    #expect(nodes.count == 2)
    for node in nodes { tree.dispatch(event: "geometryChange", value: "0,0,10,10", on: node) }
    #expect(values == [10, 10])
  }

  @Test
  func unmeasuredNestedReaderStartsAtItsParentsSizeInsteadOfZero() throws {
    let view = GeometryReader { outer in
      Text("outer=\(Int(outer.size.width))")
      GeometryReader { inner in Text("inner=\(Int(inner.size.width))") }
    }
    let tree = FiberTree(view)
    // Nothing is measured yet: both readers keep the deterministic zero size.
    #expect(tree.renderNode.htmlDescription.contains("inner=0"))

    let outerReader = try #require(tree.findNode(withEvent: "geometry"))
    tree.dispatch(event: "geometry", value: payload("0,0,900,600"), on: outerReader)
    _ = tree.update(view)
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("outer=900"))
    // The nested reader's first evaluation already sees the parent's space, so
    // width-dependent branches do not flip when the host measures it.
    #expect(html.contains("inner=900"), "\(html)")
  }
}

@Suite
@MainActor
final class GeometryReaderInvalidationScopeTests {
  private struct Shell: View {
    nonisolated(unsafe) static var shellBodies = 0
    nonisolated(unsafe) static var readerBodies = 0
    var body: some View {
      let _ = Shell.shellBodies += 1
      return VStack {
        Text("Shell")
        GeometryReader { proxy in
          let _ = Shell.readerBodies += 1
          Text("w=\(Int(proxy.size.width))")
        }
      }
    }
  }

  @Test
  func aMeasurementReevaluatesTheReaderWithoutTheViewContainingIt() throws {
    Shell.shellBodies = 0
    Shell.readerBodies = 0
    let tree = FiberTree(Shell())
    let reader = try #require(tree.findNode(withEvent: "geometry"))
    let shellBefore = Shell.shellBodies, readerBefore = Shell.readerBodies
    tree.dispatch(event: "geometry", value: "0,0,320,200", on: reader)
    _ = tree.renderNode
    #expect(tree.renderNode.htmlDescription.contains("w=320"))
    #expect(Shell.readerBodies > readerBefore)
    #expect(Shell.shellBodies == shellBefore, "the containing view must not re-evaluate")
  }
}
