import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// Lifecycle and state semantics of lazily materialized rows. Row recycling (in the browser host
/// or in the Fiber tree) must keep every behavior pinned here.
@Suite
@MainActor
final class LazyRowLifecycleTests {
  private final class Log {
    var events: [String] = []
  }

  private struct LoggedRow: View {
    let id: Int
    let log: Log
    @State var taps = 0
    var body: some View {
      Button("row\(id):\(taps)") { taps += 1 }
        .onAppear { log.events.append("appear\(id)") }
        .onDisappear { log.events.append("disappear\(id)") }
    }
  }

  private func makeTree(_ log: Log, ids: [Int] = Array(0..<20)) -> (FiberTree, FiberIdentity) {
    let view = LazyVStack { ForEach(ids, id: \.self) { LoggedRow(id: $0, log: log) } }
    let tree = FiberTree(view)
    return (tree, tree._lazyCollections()[0].ownerIdentity)
  }

  private func window(_ tree: FiberTree, _ owner: FiberIdentity, _ range: Range<Int>) {
    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(range), beforeExtent: 0, afterExtent: 0)
  }

  @Test
  func theSameWindowWithOtherSpacersKeepsItsRowsAndOnlyResizesTheSpacers() {
    let log = Log()
    let (tree, owner) = makeTree(log)
    window(tree, owner, 0..<3)
    let rows = tree.fiber(at: owner)!.children.dropFirst().dropLast().map { $0.renderNode }
    let evaluations = tree.metrics.bodyEvaluations

    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<3), beforeExtent: 0, afterExtent: 0)
    _expectEqual(tree.metrics.bodyEvaluations, evaluations, "an unchanged window renders nothing")

    _ = tree._materializeLazyCollection(ownerIdentity: owner, indices: Array(0..<3), beforeExtent: 0, afterExtent: 680)
    _expectEqual(tree.metrics.bodyEvaluations, evaluations, "new spacer sizes render no row")
    let fiber = tree.fiber(at: owner)!
    #expect(fiber.children.dropFirst().dropLast().map { ObjectIdentifier($0.renderNode) } == rows.map { ObjectIdentifier($0) })
    _expectEqual(fiber.children.last?.renderNode.styles["height"], "680.0px")
    #expect(log.events.filter { $0.hasPrefix("disappear") }.isEmpty, "the rows stay mounted")

    window(tree, owner, 1..<4)
    #expect(tree.metrics.bodyEvaluations > evaluations, "another range renders its rows")
  }

  @Test
  func rowsAppearWhenTheyEnterTheWindowAndDisappearWhenTheyLeave() {
    let log = Log()
    let (tree, owner) = makeTree(log)
    window(tree, owner, 0..<3)
    _expectEqual(log.events.filter { $0.hasPrefix("appear") }.sorted(), ["appear0", "appear1", "appear2"])
    log.events.removeAll()

    window(tree, owner, 2..<5)
    _expectEqual(log.events.filter { $0.hasPrefix("disappear") }.sorted(), ["disappear0", "disappear1"])
    _expectEqual(log.events.filter { $0.hasPrefix("appear") }.sorted(), ["appear3", "appear4"])
  }

  @Test
  func rowsThatStayInTheWindowFireNothing() {
    let log = Log()
    let (tree, owner) = makeTree(log)
    window(tree, owner, 0..<4)
    log.events.removeAll()

    window(tree, owner, 0..<4)
    window(tree, owner, 1..<4)
    _expectEqual(log.events, ["disappear0"])
  }

  @Test
  func aRowThatLeavesAndReturnsAppearsAgain() {
    let log = Log()
    let (tree, owner) = makeTree(log)
    window(tree, owner, 0..<2)
    window(tree, owner, 4..<6)
    log.events.removeAll()

    window(tree, owner, 0..<2)
    _expectEqual(log.events.filter { $0.hasPrefix("appear") }.sorted(), ["appear0", "appear1"])
  }

  @Test
  func stateInsideARowFollowsItsItemAcrossSlidingWindows() {
    let log = Log()
    let (tree, owner) = makeTree(log)
    window(tree, owner, 0..<2)
    tree.dispatch(event: "click")
    window(tree, owner, 0..<2)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("row0:1"))

    // Slides far away and back: row 0 returns with its own count, row 1 with none.
    window(tree, owner, 10..<12)
    _expectFalse(tree.root.renderNode.htmlDescription.contains("row0:"))
    window(tree, owner, 0..<2)
    let html = tree.root.renderNode.htmlDescription
    _expectTrue(html.contains("row0:1"), "state belongs to the item, not to a reused cell")
    _expectTrue(html.contains("row1:0"))
  }

  @Test
  func aRowRemovedFromTheDataDisappearsAndItsStateIsRetired() {
    let log = Log()
    let ids = Array(0..<6)
    func view(_ ids: [Int]) -> some View {
      LazyVStack { ForEach(ids, id: \.self) { LoggedRow(id: $0, log: log) } }
    }
    let tree = FiberTree(view(ids))
    let owner = tree._lazyCollections()[0].ownerIdentity
    window(tree, owner, 0..<3)
    tree.dispatch(event: "click")
    log.events.removeAll()

    _ = tree.update(view([1, 2, 3, 4, 5]))
    window(tree, owner, 0..<3)
    _expectTrue(log.events.contains("disappear0"))

    _ = tree.update(view(ids))
    window(tree, owner, 0..<3)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("row0:0"), "removed items come back with fresh state")
  }
}
