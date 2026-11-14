import Testing
import SwiftUIWeb

@Suite(.serialized)
@MainActor
struct ViewBuilderAnyViewBoundaryTests {
  private struct StatefulLeaf: View {
    let id: String
    @State private var value = 0

    var body: some View {
      Button("\(id):\(value)") { value += 1 }
    }
  }

  private struct GroupedLeaf: View {
    let id: String

    var body: some View {
      Group { StatefulLeaf(id: id) }
    }
  }

  private struct Root: View {
    let showsMiddle: Bool
    let ids: [String]

    var body: some View {
      VStack {
        StatefulLeaf(id: "before")
        HStack {
          if showsMiddle { StatefulLeaf(id: "middle") }
          ForEach(ids, id: \.self) { GroupedLeaf(id: $0) }
        }
        Group { StatefulLeaf(id: "after") }
      }
    }
  }

  private struct ExpandableRow: View {
    let id: String
    @State private var isExpanded = false
    @State private var count = 0

    var body: some View {
      VStack {
        Button("\(id):\(count)") { count += 1 }
        Button("\(id)-toggle:\(isExpanded)") { isExpanded.toggle() }
        if isExpanded {
          Group { StatefulLeaf(id: "\(id)-conditional") }
        }
      }
      .padding(1)
      .frame(maxWidth: .infinity)
      .background(Color.white)
      .border(Color.black)
    }
  }

  private struct ExpandableRoot: View {
    let ids: [String]

    var body: some View {
      VStack {
        StatefulLeaf(id: "before")
        ForEach(ids, id: \.self) { ExpandableRow(id: $0) }
        Group { StatefulLeaf(id: "after") }
      }
    }
  }

  @Test
  func partialBlockAnyViewBoundaryPreservesStateAndFiberOrderDuringCombinedTreeEdits() throws {
    let tree = FiberTree(Root(showsMiddle: true, ids: ["A", "B"]))
    let stableIDs = ["before", "A", "B", "after"]
    var originalFibers: [String: Fiber] = [:]
    for id in stableIDs {
      guard let fiber = button(id + ":0", in: tree.root) else {
        Issue.record("The initial \(id) view should be mounted")
        return
      }
      originalFibers[id] = fiber
    }

    #expect(buttonLabels(in: tree.root.renderNode) == [
      "before:0", "middle:0", "A:0", "B:0", "after:0"
    ])
    #expect(click("before:0", in: tree))
    #expect(click("B:0", in: tree))
    #expect(click("after:0", in: tree))

    _ = tree.update(Root(showsMiddle: false, ids: ["B", "A"]))
    #expect(buttonLabels(in: tree.root.renderNode) == [
      "before:1", "B:1", "A:0", "after:1"
    ])
    expectOriginalFibers(stableIDs, original: originalFibers, in: tree)

    _ = tree.update(Root(showsMiddle: true, ids: ["X", "B", "A"]))
    #expect(buttonLabels(in: tree.root.renderNode) == [
      "before:1", "middle:0", "X:0", "B:1", "A:0", "after:1"
    ])
    expectOriginalFibers(stableIDs, original: originalFibers, in: tree)
    let firstMiddle = try #require(button("middle:0", in: tree.root))
    let firstX = try #require(button("X:0", in: tree.root))
    let firstMiddleIdentity = firstMiddle.identity
    let firstXIdentity = firstX.identity

    #expect(click("middle:0", in: tree))
    #expect(click("X:0", in: tree))
    _ = tree.update(Root(showsMiddle: false, ids: ["B", "A"]))
    _ = tree.update(Root(showsMiddle: true, ids: ["X", "B", "A"]))

    #expect(buttonLabels(in: tree.root.renderNode) == [
      "before:1", "middle:0", "X:0", "B:1", "A:0", "after:1"
    ])
    let recreatedMiddle = try #require(button("middle:0", in: tree.root))
    let recreatedX = try #require(button("X:0", in: tree.root))
    #expect(recreatedMiddle.identity == firstMiddleIdentity)
    #expect(recreatedX.identity == firstXIdentity)
    #expect(ObjectIdentifier(recreatedMiddle) != ObjectIdentifier(firstMiddle))
    #expect(ObjectIdentifier(recreatedX) != ObjectIdentifier(firstX))
    expectOriginalFibers(stableIDs, original: originalFibers, in: tree)
  }

  @Test
  func conditionalBranchInsideModifiedForEachRowKeepsTheMountedOwnerState() throws {
    let tree = FiberTree(ExpandableRoot(ids: ["A", "B"]))
    let originalA = try #require(button("A:0", in: tree.root))
    let originalB = try #require(button("B:0", in: tree.root))
    let originalBefore = try #require(button("before:0", in: tree.root))
    let originalAfter = try #require(button("after:0", in: tree.root))

    #expect(click("A:0", in: tree))
    #expect(click("before:0", in: tree))
    #expect(click("after:0", in: tree))
    #expect(click("A-toggle:false", in: tree))

    #expect(button("A:1", in: tree.root)?.identity == originalA.identity)
    #expect(button("B:0", in: tree.root)?.identity == originalB.identity)
    #expect(button("before:1", in: tree.root)?.identity == originalBefore.identity)
    #expect(button("after:1", in: tree.root)?.identity == originalAfter.identity)
    #expect(button("A-conditional:0", in: tree.root) != nil)

    #expect(click("A-conditional:0", in: tree))
    #expect(click("A-toggle:true", in: tree))
    #expect(button("A-conditional:1", in: tree.root) == nil)
    #expect(click("A-toggle:false", in: tree))
    #expect(button("A:1", in: tree.root)?.identity == originalA.identity)
    #expect(button("A-conditional:0", in: tree.root) != nil)
    #expect(button("B:0", in: tree.root)?.identity == originalB.identity)
    #expect(button("before:1", in: tree.root)?.identity == originalBefore.identity)
    #expect(button("after:1", in: tree.root)?.identity == originalAfter.identity)
  }

  private func click(_ label: String, in tree: FiberTree) -> Bool {
    guard let fiber = button(label, in: tree.root) else { return false }
    tree.dispatch(event: "click", at: fiber.identity)
    _ = tree.renderNode
    return true
  }

  private func button(_ label: String, in fiber: Fiber) -> Fiber? {
    if fiber.renderNode.attributes["data-control-kind"] == "button",
       firstText(in: fiber.renderNode) == label {
      return fiber
    }
    for child in fiber.children {
      if let found = button(label, in: child) { return found }
    }
    return nil
  }

  private func expectOriginalFibers(
    _ ids: [String],
    original: [String: Fiber],
    in tree: FiberTree,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    for id in ids {
      let current = button(id + (id == "B" ? ":1" : id == "before" || id == "after" ? ":1" : ":0"), in: tree.root)
      #expect(current?.identity == original[id]?.identity, "Fiber identity for \(id) must stay with that view", sourceLocation: sourceLocation)
      #expect(current === original[id], "The retained Fiber object must stay with \(id)", sourceLocation: sourceLocation)
    }
  }

  private func buttonLabels(in node: _RenderNode) -> [String] {
    if node.attributes["data-control-kind"] == "button", let label = firstText(in: node) {
      return [label]
    }
    return node.children.flatMap(buttonLabels)
  }

  private func firstText(in node: _RenderNode) -> String? {
    if node.kind == .text { return node.text }
    for child in node.children {
      if let text = firstText(in: child) { return text }
    }
    return nil
  }
}
