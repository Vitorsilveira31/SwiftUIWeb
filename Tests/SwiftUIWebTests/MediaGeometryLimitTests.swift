import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebCore
@testable import SwiftUIWebAVFoundation
import SwiftUIWebHTML

/// Media times, springs, meshes, grids and dashes take values an application can receive from data; none may trap or
/// ask for an unbounded amount of work. The browser side is checked by `make hostile-values-browser-test`.
@Suite
@MainActor
struct MediaGeometryLimitTests {
  private func html<V: View>(_ view: V) -> String { StaticHTMLFiberRenderer().render(view) }

  @Test
  func mediaTimesSaturate() {
    #expect(CMTime(seconds: 1e17, preferredTimescale: 600).value == Int64.max)
    #expect(CMTime(seconds: -1e307, preferredTimescale: 600).value == Int64.min)
    #expect(CMTime(seconds: 2.5, preferredTimescale: 600).value == 1500)
  }

  @Test
  func springEasingIsBounded() {
    #expect(_easingNumber(1e300) == "1000000000000")
    #expect(_easingNumber(0.5) == "0.5")
  }

  @Test
  func meshesAndGridsAreBounded() {
    let mesh = html(MeshGradient(width: 70_000, height: 70_000, points: [], colors: []))
    #expect(mesh.contains("data-mesh-gradient-payload") && !mesh.contains("70000"))
    let grid = html(Grid { GridRow { Text("a").gridCellColumns(Int.max); Text("b").gridCellColumns(2) } })
    #expect(grid.contains("data-grid-cell-columns=\"1000\""))
  }

  @Test
  func hostileGeometryDoesNotHang() {
    let line = Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 1e9, y: 0)) }
    let started = ContinuousClock.now
    _ = line.strokedPath(StrokeStyle(lineWidth: 2, dash: [1e-300, 1e-300]))
    _ = line.strokedPath(StrokeStyle(lineWidth: 2, dash: [1]))
    #expect(ContinuousClock.now - started < .seconds(20))
    _ = html(Canvas { context, _ in
      let shading = GraphicsContext.Shading.radialGradient(
        Gradient(colors: [.red, .blue]), startCenter: .zero, startRadius: 0,
        endCenter: CGPoint(x: 100, y: 0), endRadius: 100.000_000_1, options: .repeat)
      context.fill(Path(CGRect(x: 0, y: 0, width: 500, height: 500)), with: shading)
    })
  }

  /// Identities from data name one path component each: "a/b" is not the path a, b, and "x#state0@Row" is not a
  /// state key's suffix.
  @Test
  func identitiesFromDataDoNotAliasPaths() {
    #expect(_FiberPath([_FiberKey("a/b")]).description != _FiberPath([_FiberKey("a"), _FiberKey("b")]).description)
    #expect(!_FiberPath([_FiberKey("x#state0@Row")]).description.contains("#"))
    #expect(_FiberPath([_FiberKey("plain"), _FiberKey(3)]).description == "plain/3")
  }
}
