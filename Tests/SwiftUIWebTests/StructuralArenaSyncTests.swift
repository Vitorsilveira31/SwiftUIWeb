import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// Targeted passes keep the structural arena current without walking the tree. After inserts, removals, a subtree
/// pass that changes the owner's root kind, and a lazy materialization that drops rows, the live arena slots are the
/// Fibers a full walk reaches, and the Fibers that left the tree are no longer live.
@Suite
@MainActor
struct StructuralArenaSyncTests {
  /// A subtree whose row count is its own state, so changing it is a targeted pass over this owner alone. Zero rows
  /// change the owner's root kind, which replaces the whole subtree.
  private struct Rows: View {
    let name: String
    @State var count = 2
    var body: some View {
      if count == 0 {
        Text("\(name) empty")
      } else {
        VStack { ForEach(0..<count, id: \.self) { Text("\(name) \($0)") } }
      }
    }
  }

  private struct Pair: View {
    let left: Rows
    let right: Rows
    var body: some View {
      VStack { left; right }
    }
  }

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

  /// The structural IDs a full walk of the tree reaches.
  private func reachableIDs(_ tree: FiberTree) -> Set<StructuralNodeID> {
    var result = Set<StructuralNodeID>()
    var pending = [tree.root]
    while let fiber = pending.popLast() {
      result.insert(fiber.structuralID)
      pending.append(contentsOf: fiber.children)
    }
    return result
  }

  /// The arena's live count equals the full walk's count, every reached node is live, and the metric agrees.
  private func expectArenaMatchesTree(_ tree: FiberTree) {
    let reachable = reachableIDs(tree)
    #expect(tree._liveStructuralNodeCount == reachable.count)
    #expect(reachable.allSatisfy { tree._isStructuralNodeLive($0) })
    #expect(tree.metrics.retainedStructuralNodes == reachable.count)
  }

  /// IDs that were reached before a pass and are not reached after it belong to removed Fibers: none is live.
  private func expectRemovedNodesRetired(_ before: Set<StructuralNodeID>, in tree: FiberTree, removing: Bool = true) {
    let removed = before.subtracting(reachableIDs(tree))
    if removing { #expect(!removed.isEmpty) }
    #expect(removed.allSatisfy { !tree._isStructuralNodeLive($0) })
  }

  @Test
  func rootPassInsertsAndRemovalsKeepTheArenaInStep() {
    let tree = FiberTree(Group { Text("A") })
    expectArenaMatchesTree(tree)
    let small = reachableIDs(tree)
    _ = tree.update(Group { Text("A"); Text("B"); Text("C") })
    expectArenaMatchesTree(tree)
    let grown = reachableIDs(tree)
    #expect(grown.count > small.count)
    _ = tree.update(Group { Text("A") })
    expectRemovedNodesRetired(grown, in: tree)
    expectArenaMatchesTree(tree)
  }

  @Test
  func subtreePassesKeepTheArenaInStepWithTheTree() {
    let left = Rows(name: "left")
    let right = Rows(name: "right")
    let tree = FiberTree(Pair(left: left, right: right))
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    expectArenaMatchesTree(tree)

    // Inserts: the left owner grows from two rows to five.
    var before = reachableIDs(tree)
    left.count = 5
    #expect(tree._hasPendingSubtreeInvalidation)
    _ = tree._drainSubtreeUpdates()
    #expect(tree.metrics.subtreeOwnerInvalidations > 0)
    #expect(tree.root.renderNode.htmlDescription.contains("left 4"))
    #expect(reachableIDs(tree).count > before.count)
    expectArenaMatchesTree(tree)

    // Removals: five rows shrink to one.
    before = reachableIDs(tree)
    left.count = 1
    _ = tree._drainSubtreeUpdates()
    #expect(!tree.root.renderNode.htmlDescription.contains("left 1"))
    expectRemovedNodesRetired(before, in: tree)
    expectArenaMatchesTree(tree)

    // The owner's root kind changes, so its whole subtree is replaced, then replaced back.
    before = reachableIDs(tree)
    left.count = 0
    _ = tree._drainSubtreeUpdates()
    #expect(tree.root.renderNode.htmlDescription.contains("left empty"))
    expectRemovedNodesRetired(before, in: tree)
    expectArenaMatchesTree(tree)

    before = reachableIDs(tree)
    left.count = 3
    _ = tree._drainSubtreeUpdates()
    #expect(tree.root.renderNode.htmlDescription.contains("left 2"))
    // The empty state was a text with no children, and the owner's Fiber keeps its node: nothing leaves the tree.
    expectRemovedNodesRetired(before, in: tree, removing: false)
    expectArenaMatchesTree(tree)
  }

  @Test
  func lazyMaterializationThatDropsRowsRetiresTheirNodes() {
    let tree = FiberTree(Filtered(), deferLazyCollections: true)
    let owner = tree._lazyCollections()[0].ownerIdentity
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<5), beforeExtent: 0, afterExtent: 0)
    expectArenaMatchesTree(tree)

    let before = reachableIDs(tree)
    tree.dispatch(event: "click")
    _ = tree.renderNode
    #expect(tree._refreshStaleLazyWindows(growTo: { _ in 0 }))
    #expect(!tree.renderNode.htmlDescription.contains("Alpha"))
    expectRemovedNodesRetired(before, in: tree)
    expectArenaMatchesTree(tree)
  }
}
