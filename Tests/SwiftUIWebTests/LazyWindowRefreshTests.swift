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

  /// A grid of two cells that grows to twenty, and whose declared columns grow from two to four when a button is pressed.
  private struct Gridded: View {
    @State private var wide = false
    var body: some View {
      VStack {
        Button("wide") { wide = true }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: wide ? 4 : 2)) {
          ForEach(0..<(wide ? 20 : 2), id: \.self) { Text("Cell \($0)") }
        }
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
    tree.fiber(at: owner)?._lazyHostMeasure = (lanes: 4, rowExtent: 30, declaredLanes: 1)
    tree.dispatch(event: "click")
    _ = tree.renderNode
    var extents: [Double] = []
    #expect(tree._refreshStaleLazyWindows(growTo: { _, extent in extents.append(extent); return 2 }))
    #expect(extents == [30])
    // The window grew by two rows of four cells, to eight; the twelve that follow are three rows of 30.
    #expect(tree.renderNode.htmlDescription.contains("height: 90.0px"))
  }

  /// A measure the host took under one declared lane count is not used once the grid declares another: the fiber keeps its
  /// identity, so the old row extent and lane count would lay out the new columns. The estimate of the new columns and their
  /// count are used instead.
  @Test
  func aMeasureTakenUnderAnOlderDeclaredCountIsNotUsedAfterItChanges() {
    let tree = FiberTree(Gridded(), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<2), beforeExtent: 0, afterExtent: 0)
    tree.fiber(at: owner)?._lazyHostMeasure = (lanes: 2, rowExtent: 30, declaredLanes: 2)
    tree.dispatch(event: "click")
    _ = tree.renderNode
    let estimate = tree._lazyCollections()[0].descriptor.estimatedExtent
    var extents: [Double] = []
    #expect(tree._refreshStaleLazyWindows(growTo: { _, extent in extents.append(extent); return 2 }))
    #expect(extents == [estimate], "the old measure's row extent 30 was used for four new columns")
    // Two rows of the four columns that were declared now: eight cells, not the four two columns would give.
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("Cell 7"), "the window did not grow by two rows of four cells")
    #expect(!html.contains("Cell 8"), "the window grew by two rows of the old two columns")
  }

  /// A grid of twenty cells whose declared columns grow from two to four when a button is pressed, with the same keys throughout.
  private struct Spaced: View {
    @State private var wide = false
    var body: some View {
      VStack {
        Button("wide") { wide = true }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: wide ? 4 : 2)) {
          ForEach(0..<20, id: \.self) { Text("Cell \($0)") }
        }
      }
    }
  }

  /// A window whose rows keep their keys while the grid declares another number of columns keeps its rows, but its spacers are
  /// computed for the new columns: the spacers it had were sized for the old ones.
  @Test
  func aWindowRecomputesItsSpacersWhenTheLaneCountChanges() {
    let tree = FiberTree(Spaced(), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(4..<8), beforeExtent: 100, afterExtent: 500)
    tree.dispatch(event: "click")
    _ = tree.renderNode
    let estimate = tree._lazyCollections()[0].descriptor.estimatedExtent
    #expect(tree._refreshStaleLazyWindows(growTo: { _, _ in 0 }))
    let fiber = tree.fiber(at: owner)
    let before = fiber?.children.first?.renderNode.attributes["data-size-h"].flatMap { Double($0) }
    let after = fiber?.children.last?.renderNode.attributes["data-size-h"].flatMap { Double($0) }
    // Four columns: the four rows before the window are one row of the estimate; the twelve after it are three rows.
    #expect(before == estimate, "the spacer before the window was sized for two columns")
    #expect(after == 3 * estimate, "the spacer after the window was sized for two columns")
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
