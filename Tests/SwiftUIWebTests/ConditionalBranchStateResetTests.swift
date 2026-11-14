import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// Removing a view from an `if`/`else if` chain ends its lifetime: showing
/// the branch again creates fresh `@State`, exactly as in SwiftUI.
@Suite
@MainActor
struct ConditionalBranchStateResetTests {
  private struct Counter: View {
    let name: String
    @State private var count = 0
    var body: some View { Button("\(name):\(count)") { count += 1 } }
  }

  private struct Root: View {
    @State private var branch = 0
    var body: some View {
      VStack {
        if branch == 1 {
          Counter(name: "one")
        } else if branch == 2 {
          Counter(name: "two")
        } else {
          Text("home")
        }
        Button("go0") { branch = 0 }
        Button("go1") { branch = 1 }
        Button("go2") { branch = 2 }
      }
    }
  }

  private struct Item: Identifiable { let id: Int }

  private struct Presenter: View {
    @State private var path = NavigationPath()
    @State private var item: Item?
    var body: some View {
      NavigationStack(path: $path) {
        VStack { Root() }
          .sheet(item: $item) { Text("sheet \($0.id)") }
      }
    }
  }

  /// A parent that reads its own `@State` and has a single stateful child: the
  /// child gets no builder key, so both share one path. Their slots must not.
  private struct ParentWithState: View {
    @State private var tint = false
    var body: some View { VStack { Root() }.background(tint ? Color.red : Color.blue) }
  }

  private struct PaddedInStack: View {
    @State private var path = NavigationPath()
    var body: some View { NavigationStack(path: $path) { VStack { Root() }.padding(37) } }
  }

  /// A child's state change below a presentation host must update only that
  /// child: siblings keep their state and the host is not remounted.
  @Test
  func childStateChangeBelowAPresentationHostKeepsSiblingState() {
    let tree = FiberTree(Presenter(), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    click("go2", tree)
    click("two:0", tree)
    click("two:1", tree)
    #expect(labels(tree.renderNode).contains("two:2"))
    click("go0", tree)
    #expect(labels(tree.renderNode).contains("home"))
    click("go2", tree)
    #expect(labels(tree.renderNode).contains("two:0"))
  }

  @Test
  func parentAndOnlyChildKeepSeparateStateSlots() {
    let tree = FiberTree(ParentWithState(), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    click("go2", tree)
    click("two:0", tree)
    click("two:1", tree)
    #expect(labels(tree.renderNode).contains("two:2"))
  }

  @Test
  func targetedStateUpdateKeepsTheEnclosingModifier() {
    let tree = FiberTree(PaddedInStack(), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    #expect(hasPadding(tree.renderNode))
    click("go2", tree)
    #expect(labels(tree.renderNode).contains("two:0"))
    #expect(hasPadding(tree.renderNode))
  }

  private func hasPadding(_ node: _RenderNode) -> Bool {
    node.styles.values.contains { $0.contains("37") } || node.children.contains { hasPadding($0) }
  }

  @Test
  func leavingAConditionalBranchDiscardsItsState() {
    let tree = FiberTree(Root(), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    click("go2", tree)
    click("two:0", tree)
    click("two:1", tree)
    #expect(labels(tree.renderNode).contains("two:2"))
    click("go0", tree)
    click("go2", tree)
    #expect(labels(tree.renderNode).contains("two:0"))
    click("two:0", tree)
    click("go1", tree)
    #expect(labels(tree.renderNode).contains("one:0"))
    click("go2", tree)
    #expect(labels(tree.renderNode).contains("two:0"))
  }

  private func click(_ label: String, _ tree: FiberTree) {
    guard let fiber = find(tree.root, label) else { Issue.record("missing \(label) in \(labels(tree.renderNode))"); return }
    tree.dispatch(event: "click", at: fiber.identity)
    _ = tree.renderNode
  }

  private func find(_ fiber: Fiber, _ label: String) -> Fiber? {
    if fiber.renderNode.attributes["data-control-kind"] == "button", labels(fiber.renderNode) == [label] { return fiber }
    for child in fiber.children { if let f = find(child, label) { return f } }
    return nil
  }

  private func labels(_ node: _RenderNode) -> [String] {
    if node.kind == .text, let text = node.text { return [text] }
    return node.children.flatMap(labels)
  }
}
