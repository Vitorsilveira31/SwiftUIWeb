import Dispatch
import Testing
import Foundation
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
final class MeshGradientTests {
  private let points: [SIMD2<Float>] = [
    .init(0, 0), .init(0.5, 0), .init(1, 0),
    .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
    .init(0, 1), .init(0.5, 1), .init(1, 1)
  ]

  @Test
  func testSwiftUIPointsInitializerPreservesMeshSemantics() {
    let mesh = MeshGradient(width: 3, height: 3, points: points, colors: [
      .red, .purple, .blue,
      .orange, .white, .green,
      .yellow, .gray, .black
    ])
    _expectEqual(mesh.width, 3)
    _expectEqual(mesh.height, 3)
    _expectEqual(mesh.points, points)
    _expectEqual(mesh.colors._values.count, 9)
    _expectEqual(mesh.background, .clear)
    _expectTrue(mesh.smoothsColors)
    _expectEqual(mesh.colorSpace, .device)
  }

  @Test
  func testBezierAndLocationsInitializersRemainSourceCompatible() {
    let bezier = MeshGradient.BezierPoint(
      position: .init(0, 0),
      leadingControlPoint: .init(0, 0),
      topControlPoint: .init(0, 0),
      trailingControlPoint: .init(0.5, 0),
      bottomControlPoint: .init(0, 0.5)
    )
    let mesh = MeshGradient(
      width: 1,
      height: 1,
      locations: .bezierPoints([bezier]),
      colors: .colors([.red]),
      background: .blue,
      smoothsColors: false,
      colorSpace: .perceptual
    )
    _expectEqual(mesh.points, [.init(0, 0)])
    _expectEqual(mesh.locations, .bezierPoints([bezier]))
    _expectEqual(mesh.background, .blue)
    _expectFalse(mesh.smoothsColors)
    _expectEqual(mesh.colorSpace, .perceptual)
    let descriptor = FiberTree(mesh, deferLazyCollections: false, rootLayoutProposal: ProposedViewSize(width: 80, height: 40)).renderNode
    let payload = descriptor.attributes["data-mesh-gradient-payload"] ?? ""
    _expectTrue(payload.contains("\"bezierPoints\""))
    _expectTrue(payload.contains("\"trailing\":[0.5,0]"))
    _expectNoThrow(try JSONSerialization.jsonObject(with: Data(payload.utf8)))

    let resolvedLocations = MeshGradient(
      width: 1,
      height: 1,
      locations: .points([.init(0, 0)]),
      colors: .resolvedColors([.init(red: 0, green: 1, blue: 0)])
    )
    _expectEqual(resolvedLocations.colors._values.first, Color(red: 0, green: 1, blue: 0))

    let resolved = MeshGradient(
      width: 1,
      height: 1,
      points: [.init(0, 0)],
      resolvedColors: [.init(red: 1, green: 0, blue: 0)]
    )
    _expectEqual(resolved.colors._values.first, Color(red: 1, green: 0, blue: 0))
  }

  @Test
  func testMeshGradientEmitsRetainedCanvasDescriptorAndResponsiveProposal() {
    let mesh = MeshGradient(width: 3, height: 3, points: points, colors: Array(repeating: .blue, count: 9))
    let tree = FiberTree(mesh, deferLazyCollections: false, rootLayoutProposal: ProposedViewSize(width: 640, height: 360))
    let node = tree.renderNode
    _expectEqual(node.kind, .element("canvas"))
    _expectEqual(node.attributes["data-mesh-gradient"], "true")
    _expectEqual(node.attributes["data-mesh-gradient-width"], "3")
    _expectEqual(node.attributes["data-mesh-gradient-height"], "3")
    _expectEqual(node.attributes["data-mesh-gradient-size"], "640,360")
    _expectEqual(node.styles["width"], "640px")
    _expectEqual(node.styles["height"], "360px")
    _expectTrue(node.attributes["data-mesh-gradient-payload"]?.contains("\"points\"") == true)
    _expectNotNil(node.attributes["data-mesh-gradient-fingerprint"])
    let html = StaticHTMLFiberRenderer().render(mesh)
    _expectTrue(html.contains("data-mesh-gradient=\"true\""))
    _expectTrue(html.contains("<canvas"))
  }

  @Test
  func testMeshGradientWorksAsShapeStyleBackgroundWithoutWebTypes() {
    let view = Text("Mesh card")
      .padding(12)
      .background(MeshGradient(width: 3, height: 3, points: points, colors: Array(repeating: .purple, count: 9)))
    let node = FiberTree(view).renderNode
    _expectEqual(node.classes, ["backdrop-layer"])
    _expectEqual(node.children.count, 2)
    _expectEqual(node.children.first?.attributes["data-background-mesh-gradient"], "true")
    _expectEqual(node.children.first?.attributes["data-mesh-gradient"], "true")
    _expectEqual(node.children.first?.kind, .element("canvas"))
    // The padded view stays the content layer so the mesh paints the padded bounds.
    _expectEqual(node.children.last?.attributes["data-layout-kind"], "padding")
    _expectEqual(node.children.last?.children.first?.kind, .text)
    _expectFalse(node.htmlDescription.contains("JavaScript"))

    let erased = Text("Erased mesh")
      .background(AnyShapeStyle(MeshGradient(width: 2, height: 2, points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)], colors: [.red, .blue, .green, .orange])))
    _expectEqual(FiberTree(erased).renderNode.children.first?.attributes["data-mesh-gradient"], "true")

    let painted = Circle().fill(MeshGradient(width: 2, height: 2, points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)], colors: [.red, .blue, .green, .orange]))
    let paintedNode = FiberTree(painted).renderNode
    _expectEqual(paintedNode.kind, .element("canvas"))
    _expectEqual(paintedNode.attributes["data-shape"], "circle")
    _expectEqual(paintedNode.styles["border-radius"], "9999px")
  }

  @Test
  func testMeshGradientNormalizesIncompleteAndNonFiniteGridData() throws {
    let mesh = MeshGradient(
      width: 2,
      height: 2,
      points: [.init(.nan, .infinity)],
      colors: [.red, .blue, .green, .orange, .purple],
      background: .black
    )
    let payload = try #require(FiberTree(mesh).renderNode.attributes["data-mesh-gradient-payload"])
    let decoded = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
    // WebFoundation's JSONSerialization yields integral numbers as Int and others as Double: without Objective-C's
    // NSNumber bridging an `Any` holding one cannot cast to the other, so read either.
    let rows = try #require(decoded["points"] as? [[Any]])
    let points = rows.map { $0.map { ($0 as? Int).map(Float.init) ?? ($0 as? Double).map(Float.init) } }
    let colors = try #require(decoded["colors"] as? [String])
    #expect(points == [[0, 0], [1, 0], [0, 1], [1, 1]])
    #expect(colors.count == 4)
    #expect(colors.last == Color.orange.cssValue)
    #expect(!payload.contains(Color.purple.cssValue))

    let missingBezier = MeshGradient(width: 1, height: 1, bezierPoints: [], colors: [])
    let fallbackPayload = try #require(FiberTree(missingBezier).renderNode.attributes["data-mesh-gradient-payload"])
    #expect(fallbackPayload.contains("\"bezierPoints\":[null]"))
    #expect(fallbackPayload.contains("\"points\":[[0,0]]"))
  }

  @Test
  func testMeshGradientStateUpdatesFingerprintAndAnimationMetadata() {
    struct Fixture: View {
      @State private var alternate = false
      var body: some View {
        Button("Toggle") { alternate.toggle() }
          .background(
            MeshGradient(
              width: 2,
              height: 2,
              points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)],
              colors: alternate ? [.red, .orange, .purple, .blue] : [.blue, .purple, .orange, .red]
            )
          )
          .animation(.easeInOut(duration: 0.25), value: alternate)
      }
    }

    let fixture = Fixture()
    let tree = FiberTree(fixture)
    let before = tree.renderNode
    let beforeFingerprint = before.children.first?.attributes["data-mesh-gradient-fingerprint"]
    tree.dispatch(event: "click")
    _ = tree.update(fixture)
    let after = tree.renderNode
    let background = after.children.first
    _expectNotEqual(beforeFingerprint, background?.attributes["data-mesh-gradient-fingerprint"])
    _expectTrue(background?.attributes["data-mesh-gradient-animation"]?.contains("250ms") == true)
  }

  @Test
  func testMeshGradientRecordingBenchmarkMatrix() {
    for dimensions in [(2, 2), (4, 4), (8, 8)] {
      let count = dimensions.0 * dimensions.1
      let points = (0..<count).map { index in
        SIMD2<Float>(
          Float(index % dimensions.0) / Float(max(1, dimensions.0 - 1)),
          Float(index / dimensions.0) / Float(max(1, dimensions.1 - 1))
        )
      }
      let start = DispatchTime.now().uptimeNanoseconds
      let node = FiberTree(MeshGradient(width: dimensions.0, height: dimensions.1, points: points, colors: Array(repeating: .blue, count: count))).renderNode
      let elapsed = DispatchTime.now().uptimeNanoseconds - start
      print("mesh-gradient-recording,vertices=\(count),elapsedNs=\(elapsed),payloadBytes=\(node.attributes["data-mesh-gradient-payload"]?.utf8.count ?? 0)")
      _expectEqual(node.attributes["data-mesh-gradient-width"], String(dimensions.0))
      _expectLessThan(node.attributes["data-mesh-gradient-payload"]?.utf8.count ?? 0, 8_192)
    }
  }
}
