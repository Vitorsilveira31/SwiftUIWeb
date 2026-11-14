import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// `Fiber.version` is what lets a host skip subtrees that did not change: it
/// must rise for a changed fiber and every ancestor, and only for those.
@Suite
@MainActor
struct FiberVersionTests {
  private struct Card: View {
    let name: String
    @State private var taps = 0
    var body: some View {
      VStack { Button("\(name):\(taps)") { taps += 1 }; Text("static-\(name)") }
    }
  }

  private struct Page: View {
    var body: some View {
      VStack {
        Card(name: "a")
        Card(name: "b")
        Card(name: "c")
      }
    }
  }

  private func fiber(_ label: String, in fiber: Fiber) -> Fiber? {
    if fiber.renderNode.attributes["data-control-kind"] == "button", labels(fiber.renderNode) == [label] { return fiber }
    for child in fiber.children { if let found = self.fiber(label, in: child) { return found } }
    return nil
  }

  private func labels(_ node: _RenderNode) -> [String] {
    if node.kind == .text, let text = node.text { return [text] }
    return node.children.flatMap(labels)
  }

  private func chain(of target: Fiber, in tree: FiberTree) -> [Fiber] {
    var out: [Fiber] = []
    var current: Fiber? = target
    while let f = current { out.append(f); current = f.parentIdentity.flatMap { tree.fiber(at: $0) } }
    return out
  }

  private func allFibers(_ f: Fiber) -> [Fiber] { [f] + f.children.flatMap(allFibers) }

  @Test
  func aStateChangeRaisesTheVersionOfTheChangedPathOnly() throws {
    let tree = FiberTree(Page(), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    _ = tree.renderNode
    let covered = tree._advanceEpoch()                 // everything so far is "published"
    #expect(allFibers(tree.root).allSatisfy { $0.version <= covered })

    let button = try #require(fiber("b:0", in: tree.root))
    tree.dispatch(event: "click", at: button.identity)
    _ = tree.renderNode

    let path = Set(chain(of: try #require(fiber("b:1", in: tree.root)), in: tree).map { $0.identity })
    let changed = allFibers(tree.root).filter { $0.version > covered }
    #expect(!changed.isEmpty)
    // Everything that changed lies on the path from the root to the button...
    #expect(changed.allSatisfy { fiber in
      path.contains(fiber.identity) || path.contains(where: { fiber.identity.path.starts(with: $0.path) })
    })
    // ...and the untouched siblings (a, c) stayed at their old version.
    for name in ["a", "c"] {
      let sibling = try #require(fiber("\(name):0", in: tree.root))
      #expect(sibling.version <= covered, "\(name) must be unchanged")
    }
  }

  @Test
  func aNewFiberStartsInTheCurrentEpochSoItIsNeverTakenForPublished() {
    let tree = FiberTree(Page(), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    let before = tree._epoch
    #expect(allFibers(tree.root).allSatisfy { $0.version == before })
    _ = tree._advanceEpoch()
    #expect(tree._epoch == before + 1)
  }
}
