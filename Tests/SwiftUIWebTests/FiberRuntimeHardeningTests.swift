import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@testable import SwiftUIWebFeatures

/// A stateless leaf whose only change between two renders is an instance-bound attribute (the kind the static
/// template key used to leave out).
private struct InstanceAttributeProbe: View {
  typealias Body = Never
  let ratio: String

  func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.text = "probe"
    node.attributes["data-image-ratio"] = ratio
    return node
  }
}

private struct HardeningOutlineNode: Identifiable {
  var id: Int
  var title: String
  var children: [HardeningOutlineNode]?
}

// `StorageRuntime` is process-global, so these tests run serialized, as the other storage suites do.
@Suite(.serialized, .processGlobalState)
@MainActor
final class FiberRuntimeHardeningTests {
  deinit {
    StorageRuntime.install(nil)
  }

  @Test
  func testInstanceBoundAttributeChangeReachesRetainedStatelessNode() {
    let tree = FiberTree(InstanceAttributeProbe(ratio: "1.0"))
    _expectTrue(tree.root.renderNode.attributes["data-image-ratio"] == "1.0")

    let mutations = tree.update(InstanceAttributeProbe(ratio: "2.0"))

    _expectTrue(tree.root.renderNode.attributes["data-image-ratio"] == "2.0", "the second render's attribute must reach the node")
    _expectFalse(mutations.isEmpty, "a changed instance-bound attribute must produce a DOM update")
  }

  @Test
  func testInvalidatingOneStorageKeyKeepsOtherKeysCached() {
    var values: [String: String] = ["hardening.a": "1", "hardening.b": "2"]
    var reads = 0
    StorageRuntime.install(StorageAdapter(
      read: { key in reads += 1; return values[key] },
      write: { values[$0] = $1 }
    ))

    _expectTrue(StorageRuntime.read("hardening.a") == "1")
    _expectTrue(StorageRuntime.read("hardening.b") == "2")
    _expectEqual(reads, 2)

    values["hardening.a"] = "changed"
    values["hardening.b"] = "changed"
    StorageRuntime.invalidateCache(scope: .app, key: "hardening.a")

    _expectTrue(StorageRuntime.read("hardening.a") == "changed", "the invalidated key reloads from the host")
    _expectTrue(StorageRuntime.read("hardening.b") == "2", "the other key stays cached")
    _expectEqual(reads, 3)
  }

  @Test
  func testRowBindingResolvesRepeatedIdentifierToFirstPreOrderMatch() {
    var nodes = [
      HardeningOutlineNode(id: 5, title: "outer", children: [
        HardeningOutlineNode(id: 7, title: "inner", children: nil)
      ]),
      HardeningOutlineNode(id: 7, title: "second", children: nil)
    ]
    let binding = Binding<[HardeningOutlineNode]>(get: { nodes }, set: { nodes = $0 })
    var titlesReadByRows: [String] = []
    // Reads the row's binding while the row renders and returns its title, so the builder only sees an expression.
    let readTitle: (Binding<HardeningOutlineNode>) -> String = { node in
      let title = node.wrappedValue.title
      titlesReadByRows.append(title)
      return title
    }

    _ = StaticHTMLFiberRenderer().render(
      OutlineGroup(binding, children: \.children) { (node: Binding<HardeningOutlineNode>) in
        Text(readTitle(node))
      }
    )

    // Pre-order visits "outer", then its child "inner" (id 7), then the root "second" (id 7). The second row's
    // binding must read the first match, as the search always did.
    _expectTrue(titlesReadByRows.contains("inner"), "a repeated id resolves to its first pre-order occurrence")
    _expectFalse(titlesReadByRows.contains("second"))
  }

  @Test
  func testCollapsedDeepOutlineReadsItsRootWithoutIndexingTheChain() {
    // A chain 1,500 levels deep, shown collapsed: only the root row renders and reads its binding.
    var chain = HardeningOutlineNode(id: 1_500, title: "leaf", children: nil)
    for id in stride(from: 1_499, through: 0, by: -1) { chain = HardeningOutlineNode(id: id, title: "node \(id)", children: [chain]) }
    var nodes = [chain]
    let binding = Binding<[HardeningOutlineNode]>(get: { nodes }, set: { nodes = $0 })
    var titles: [String] = []
    _ = StaticHTMLFiberRenderer().render(
      OutlineGroup(binding, children: \.children) { (node: Binding<HardeningOutlineNode>) in
        Text({ () -> String in titles.append(node.wrappedValue.title); return node.wrappedValue.title }())
      }
    )
    _expectTrue(titles.contains("node 0"))
  }
}
