import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A browser session encloses the application in the window (`_geometryHint` at the root): before the host measures
/// it, an application's outermost geometry reader renders at the window instead of zero, so what it lays out from that
/// size does not move a publication later. Nothing else sees the window: layout proposals are unchanged.
@Suite
@MainActor
struct GeometryReaderFirstRenderTests {
  /// The widths a reader rendered at, in order.
  private final class Widths { var values: [Int] = [] }

  private struct Shell: View {
    let widths: Widths
    var body: some View {
      GeometryReader { proxy in
        let _ = widths.values.append(Int(proxy.size.width))
        Text("width \(Int(proxy.size.width))")
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func window(_ width: CGFloat, _ height: CGFloat) -> EnvironmentValues {
    var environment = EnvironmentValues()
    environment._geometryHint = CGSize(width: width, height: height)
    return environment
  }

  @Test
  func theOutermostReaderStartsAtTheWindow() {
    let widths = Widths()
    let tree = FiberTree(Shell(widths: widths), environment: window(1280, 800), deferLazyCollections: true)
    #expect(widths.values.first == 1280, "the reader rendered at \(widths.values)")
    #expect(tree.renderNode.htmlDescription.contains("width 1280"))
  }

  @Test
  func withoutAWindowTheOutermostReaderStartsAtZero() {
    let widths = Widths()
    _ = FiberTree(Shell(widths: widths), deferLazyCollections: true)
    #expect(widths.values.first == 0, "the reader rendered at \(widths.values)")
  }

  @Test
  func theHostsMeasurementReplacesTheWindow() throws {
    let widths = Widths()
    let tree = FiberTree(Shell(widths: widths), environment: window(1280, 800), deferLazyCollections: true)
    let reader = try #require(tree.findNode(withEvent: "geometry"))
    tree.dispatch(event: "geometry", value: "0,0,1100,700", on: reader)
    #expect(tree.renderNode.htmlDescription.contains("width 1100"))
    #expect(widths.values.last == 1100)
  }
}
