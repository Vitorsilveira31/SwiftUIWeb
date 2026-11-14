import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A translucent solid `Rectangle` fill is painted once: the CSS background paints it, and the SVG path that
/// carries the same paint value draws nothing.
@Suite
@MainActor
struct TranslucentRectanglePaintsOnceTests {
  private func shape(in node: _RenderNode) -> _RenderNode? {
    if node.classes.contains("shape-layer"), node.attributes["data-shape"] == "rectangle" { return node }
    for child in node.children { if let found = shape(in: child) { return found } }
    return nil
  }

  private func path(in node: _RenderNode) -> _RenderNode? {
    node.children.first { if case .element("path") = $0.kind { return true }; return false }
  }

  @Test func solidColorFillIsPaintedByTheBackgroundOnly() throws {
    let tree = FiberTree(Rectangle().fill(Color.black.opacity(0.45)).frame(width: 100, height: 100))
    let rectangle = try #require(shape(in: tree.renderNode))
    // A solid rectangle is one CSS box: the background is the only paint, so there is no path to draw it again.
    #expect(rectangle.kind == .element("div"))
    #expect(rectangle.styles["background"] == Color.black.opacity(0.45).cssValue)
    #expect(path(in: rectangle) == nil)
  }

  @Test func solidColorPathFallbackIsPaintedByTheBackgroundOnly() throws {
    // Antialiasing off keeps the SVG path; its background and path must still not paint twice.
    let tree = FiberTree(Rectangle().fill(Color.black.opacity(0.45), style: FillStyle(antialiased: false)).frame(width: 100, height: 100))
    let rectangle = try #require(shape(in: tree.renderNode))
    #expect(rectangle.kind == .element("svg"))
    #expect(rectangle.styles["background"] == Color.black.opacity(0.45).cssValue)
    let path = try #require(path(in: rectangle))
    // The path keeps the paint value but draws nothing.
    #expect(path.styles["fill"] == Color.black.opacity(0.45).cssValue)
    #expect(path.styles["fill-opacity"] == "0")
  }

  @Test func gradientFillKeepsItsPathPaint() throws {
    let tree = FiberTree(
      Rectangle().fill(LinearGradient(colors: [.black, .white], startPoint: .top, endPoint: .bottom)).frame(width: 100, height: 100)
    )
    let rectangle = try #require(shape(in: tree.renderNode))
    let path = try #require(path(in: rectangle))
    #expect(path.styles["fill"] != "none")
    #expect(path.styles["fill-opacity"] == nil)
  }
}
