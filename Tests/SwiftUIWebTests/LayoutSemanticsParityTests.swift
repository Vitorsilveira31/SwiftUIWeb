import Testing
import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// Swift -> browser semantic metadata for SwiftUI behaviors that the layout
/// engine can only honor when the renderer emits them: inherited line limits,
/// grid item spacing/alignment and `Grid`/`GridRow` tables.
@Suite
@MainActor
struct LayoutSemanticsParityTests {
  private func nodes(_ node: _RenderNode, where predicate: (_RenderNode) -> Bool) -> [_RenderNode] {
    (predicate(node) ? [node] : []) + node.children.flatMap { nodes($0, where: predicate) }
  }

  @Test
  func lineLimitOnAContainerClampsEveryTextInside() {
    // A ButtonStyle applies `.lineLimit(1)` to its whole label.
    let tree = FiberTree(HStack { Text("Aprovar"); Text("A") }.lineLimit(1))
    let texts = nodes(tree.renderNode) { $0.kind == .text }
    #expect(texts.count == 2)
    for text in texts {
      #expect(text.styles["-webkit-line-clamp"] == "1")
      // One line truncates with an ellipsis inside a word, as SwiftUI does: a block that does not wrap.
      #expect(text.styles["display"] == "block")
      #expect(text.styles["white-space"] == "nowrap")
      #expect(text.styles["text-overflow"] == "ellipsis")
    }
    let stacks = nodes(tree.renderNode) { $0.classes.contains("hstack") }
    #expect(stacks.allSatisfy { $0.styles["-webkit-line-clamp"] == nil })
  }

  @Test
  func innerLineLimitWinsAndNilRemovesTheLimit() {
    let tree = FiberTree(VStack { Text("Two").lineLimit(2); Text("Free").lineLimit(nil) }.lineLimit(1))
    let texts = nodes(tree.renderNode) { $0.kind == .text }
    #expect(texts.first { $0.text == "Two" }?.styles["-webkit-line-clamp"] == "2")
    #expect(texts.first { $0.text == "Free" }?.styles["-webkit-line-clamp"] == nil)
  }

  @Test
  func lazyGridEmitsItemSpacingAlignmentAndRowSpacing() {
    let grid = LazyVGrid(
      columns: [GridItem(.flexible(), spacing: 30, alignment: .top), GridItem(.fixed(90))],
      alignment: .leading, spacing: 14
    ) { Text("Cell") }._render(in: _RenderContext())
    #expect(grid.attributes["data-grid-tracks"] == "flexible:10.0:inf:30.0:0.5:0|fixed:90.0:90.0:::")
    #expect(grid.attributes["data-layout-gap"] == "8.0")
    #expect(grid.attributes["data-row-spacing"] == "14.0")
    #expect(grid.attributes["data-align-x"] == "0")
    #expect(grid.attributes["data-align-y"] == "0.5")

    let rows = LazyHGrid(rows: [GridItem()], alignment: .bottom, spacing: 6) { Text("Cell") }._render(in: _RenderContext())
    #expect(rows.attributes["data-row-spacing"] == "6.0")
    #expect(rows.attributes["data-align-x"] == "0.5")
    #expect(rows.attributes["data-align-y"] == "1")
  }

  @Test
  func gridAndGridRowAreSemanticTables() {
    let tree = FiberTree(
      Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 8) {
        GridRow { Text("A"); Text("B") }
        GridRow(alignment: .bottom) { Text("C"); Text("D") }
      }
    )
    let grid = try! #require(nodes(tree.renderNode) { $0.classes.contains("regular-grid") }.first)
    #expect(grid.attributes["data-layout-kind"] == "table")
    #expect(grid.attributes["data-layout-gap"] == "14.0")
    #expect(grid.attributes["data-row-spacing"] == "8.0")
    #expect(grid.attributes["data-align-x"] == "0")
    #expect(grid.attributes["data-align-y"] == "0")
    let rows = nodes(tree.renderNode) { $0.classes.contains("grid-row") }
    #expect(rows.count == 2)
    #expect(rows.allSatisfy { $0.attributes["data-layout-kind"] == "gridrow" })
    #expect(rows[0].attributes["data-row-align-y"] == nil)
    #expect(rows[1].attributes["data-row-align-y"] == "1")
  }
}
