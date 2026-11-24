import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A lazy window materialized before its collection changed is rendered again against the current data, so the next
/// publication never shows rows of the previous data.
@Suite
@MainActor
struct LazyWindowRefreshTests {
  private struct Filtered: View {
    @State private var narrow = false
    private var rows: [String] { narrow ? ["Gamma"] : ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"] }
    var body: some View {
      VStack {
        Button("narrow") { narrow = true }
        LazyVStack { ForEach(rows, id: \.self) { Text($0) } }
      }
    }
  }

  /// A list that shows `before` rows until a button switches it to `after` rows.
  private struct Growing: View {
    let before: Int
    let after: Int
    @State private var grown = false
    var body: some View {
      VStack {
        Button("grow") { grown = true }
        LazyVStack { ForEach(0..<(grown ? after : before), id: \.self) { Text("Item \($0)") } }
      }
    }
  }

  /// A list whose rows capture the parent's state: the same keys before and after the click.
  private struct Starring: View {
    @State private var starred = false
    var body: some View {
      VStack {
        Button("star") { starred = true }
        LazyVStack { ForEach(0..<3, id: \.self) { Text("Row \($0)\(starred ? " ★" : "")") } }
      }
    }
  }

  /// Rows of a list that shrank from five items to one are gone from the first publication after the change.
  @Test
  func rowsOfAShrunkCollectionLeaveWithTheChange() {
    let tree = FiberTree(Filtered(), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    tree.dispatch(event: "click")
    // Rendering the parent again keeps the rows it had: they still show the previous data.
    #expect(tree.renderNode.htmlDescription.contains("Alpha"))
    #expect(tree._refreshStaleLazyWindows(growTo: { _, _ in 0 }))
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("Gamma"))
    for removed in ["Alpha", "Beta", "Delta", "Epsilon"] {
      #expect(!html.contains(removed), "\(removed) belongs to the previous data")
    }
  }

  /// A window that reached the end of a list which then grows is extended over the new rows in the same publication.
  @Test
  func aWindowThatReachedTheEndExtendsOverTheNewRows() {
    let tree = FiberTree(Growing(before: 2, after: 6), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<2), beforeExtent: 0, afterExtent: 0)
    tree.dispatch(event: "click")
    _ = tree.renderNode
    #expect(tree._refreshStaleLazyWindows(growTo: { _, _ in 10 }))
    let html = tree.renderNode.htmlDescription
    for index in 0..<6 {
      #expect(html.contains("Item \(index)"), "item \(index) is missing after growth")
    }
  }

  /// A window that stopped before the end of its list does not grow when the list does: its rows are the same ones (they are
  /// rendered again, as any window whose collection was evaluated again, but no row is added).
  @Test
  func aWindowThatDidNotReachTheEndDoesNotGrow() {
    let tree = FiberTree(Growing(before: 4, after: 8), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<2), beforeExtent: 0, afterExtent: 0)
    tree.dispatch(event: "click")
    _ = tree.renderNode
    _ = tree._refreshStaleLazyWindows(growTo: { _, _ in 10 })
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("Item 0") && html.contains("Item 1"))
    for index in 2..<8 {
      #expect(!html.contains("Item \(index)"), "item \(index) is outside the window")
    }
  }

  /// A parent that renders again with the same range and keys renders the rows again too: what its closure captured may
  /// have changed, and the host's next window request would keep the rows it finds "materialized from the current data".
  @Test
  func aWindowWithTheSameKeysRendersItsRowsAgain() {
    let tree = FiberTree(Starring(), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<3), beforeExtent: 0, afterExtent: 0)
    #expect(!tree.renderNode.htmlDescription.contains("★"))
    tree.dispatch(event: "click")
    _ = tree.renderNode
    #expect(tree._refreshStaleLazyWindows(growTo: { _, _ in 10 }))
    let html = tree.renderNode.htmlDescription
    for index in 0..<3 { #expect(html.contains("Row \(index) ★"), "row \(index) shows the new state in the publication that answers the click") }
    // The window request that follows every commit changes nothing and does not bring the old rows back.
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<3), beforeExtent: 0, afterExtent: 0)
    #expect(tree.renderNode.htmlDescription.contains("Row 2 ★"))
    #expect(!tree._refreshStaleLazyWindows(growTo: { _, _ in 10 }), "nothing is stale any more")
  }

  /// The spacer the host sized from what it measured survives the rows being rendered again.
  @Test
  func aWindowRenderedAgainKeepsItsMeasuredSpacers() {
    let tree = FiberTree(Starring(), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<3), beforeExtent: 0, afterExtent: 1234)
    tree.dispatch(event: "click")
    _ = tree.renderNode
    #expect(tree._refreshStaleLazyWindows(growTo: { _, _ in 10 }))
    #expect(tree.renderNode.htmlDescription.contains("height: 1234.0px"))
  }

  /// The rows the host laid out size the cells that are not shown, and the window grows by whole rows of them: Swift knows only
  /// the columns a grid declared, not how many the browser laid out.
  @Test
  func aCellExtentTheHostMeasuredSizesTheCellsNotShown() {
    let tree = FiberTree(Growing(before: 2, after: 20), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<2), beforeExtent: 0, afterExtent: 0)
    tree.fiber(at: owner)?._lazyHostMeasure = (lanes: 4, rowExtent: 30)
    tree.dispatch(event: "click")
    _ = tree.renderNode
    var extents: [Double] = []
    #expect(tree._refreshStaleLazyWindows(growTo: { _, extent in extents.append(extent); return 2 }))
    #expect(extents == [30])
    // The window grew by two rows of four cells, to eight; the twelve that follow are three rows of 30.
    #expect(tree.renderNode.htmlDescription.contains("height: 90.0px"))
  }

  /// A window materialized from the collection's current revision is left alone, so nothing is refreshed.
  @Test
  func aWindowOfTheCurrentRevisionIsNotRefreshed() {
    let tree = FiberTree(Growing(before: 4, after: 8), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<2), beforeExtent: 0, afterExtent: 0)
    #expect(!tree._refreshStaleLazyWindows(growTo: { _, _ in 10 }))
  }
}
