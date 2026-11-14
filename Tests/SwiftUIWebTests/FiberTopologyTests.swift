import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
import SwiftUIWebHTML

@Suite(.serialized)
@MainActor
struct FiberTopologyTests {
  @Test
  func realFiberMatchingKeepsTopology() {
    let tree = FiberTree(ForEach([1, 2, 3], id: \.self) { Text("Row \($0)") })
    let first = tree.root.children[0], third = tree.root.children[2]
    _ = tree.update(ForEach([3, 4, 1], id: \.self) { Text("Row \($0)") })
    _expectTrue(tree.root.children[0] === third)
    _expectTrue(tree.root.children[2] === first)
    assertTopology(tree, tree.root)
  }

  @Test
  func typedKeysDoNotBecomeLossyHashesOrDescriptions() {
    struct ID: Hashable, CustomStringConvertible {
      var number: Int
      var description: String { "same description" }
      func hash(into hasher: inout Hasher) { hasher.combine(0) }
    }
    let first = ID(number: 1), second = ID(number: 2)
    let tree = FiberTree(ForEach([first, second], id: \.self) { Text("\($0.number)") })
    let a = tree.root.children[0], b = tree.root.children[1]
    _ = tree.update(ForEach([second, first], id: \.self) { Text("\($0.number)") })
    _expectTrue(tree.root.children[0] === b)
    _expectTrue(tree.root.children[1] === a)
    assertTopology(tree, tree.root)
  }

  @Test
  func independentTreesKeepSeparateArenas() {
    let first = FiberTree(Text("first"))
    let second = FiberTree(VStack { Text("second"); Text("third") })
    _ = first.update(Text("updated"))
    // One tree's arena synchronization must not retire another tree's nodes.
    assertTopology(second, second.root)
    _ = second.update(VStack { Text("next"); Text("last") })
    assertTopology(first, first.root)
    _expectTrue(first.renderNode.htmlDescription.contains("updated"))
  }

  @Test
  func keyedStateStillFollowsTheSwiftUIAPI() {
    struct Row: View {
      let id: Int
      @State var count = 0
      var body: some View { Button("\(id):\(count)") { count += 1 } }
    }
    let view = ForEach([1, 2], id: \.self) { Row(id: $0) }
    let tree = FiberTree(view)
    tree.dispatch(event: "click")
    _ = tree.update(view)
    _ = tree.update(ForEach([2, 1], id: \.self) { Row(id: $0) })
    _expectTrue(tree.renderNode.htmlDescription.contains("1:1"))
    _expectTrue(tree.renderNode.htmlDescription.contains("2:0"))
    assertTopology(tree, tree.root)
  }

  private func assertTopology(_ tree: FiberTree, _ node: Fiber, file: StaticString = #filePath, line: UInt = #line) {
    _expectEqual(tree._childIDs(of: node), node.children.map(\.structuralID), file: file, line: line)
    for child in node.children { assertTopology(tree, child, file: file, line: line) }
  }
}
