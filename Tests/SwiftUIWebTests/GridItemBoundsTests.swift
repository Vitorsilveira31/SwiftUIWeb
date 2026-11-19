import Testing
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures

@Suite
@MainActor
struct GridItemBoundsTests {
  // This is the Swift -> host wire boundary. The layout's geometry tests own
  // distribution; this contract catches a maximum discarded before it arrives.
  @Test(arguments: [false, true])
  func boundedTracksReachBothGridAxes(horizontal: Bool) {
    let tracks = [GridItem(.adaptive(minimum: 80, maximum: 160)),
                  GridItem(.flexible(minimum: 24, maximum: 120)), GridItem()]
    let node: _RenderNode
    if horizontal {
      node = LazyHGrid(rows: tracks) { Text("Cell") }._render(in: _RenderContext())
    } else {
      node = LazyVGrid(columns: tracks) { Text("Cell") }._render(in: _RenderContext())
    }
    #expect(node.attributes["data-grid-tracks"] == "adaptive:80.0:160.0:::|flexible:24.0:120.0:::|flexible:10.0:inf:::")
    let property = horizontal ? "grid-template-rows" : "grid-template-columns"
    // A column's adaptive minimum is capped at the grid's width, so it never overflows the grid; a row's is not.
    let adaptiveFloor = horizontal ? "80px" : "min(80px, 100%)"
    #expect(node.styles[property] == "repeat(auto-fit, minmax(\(adaptiveFloor), 160px)) minmax(24px, 120px) minmax(10px, 1fr)")
  }
}
