import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
import SwiftUIWeb

/// Modifier layers share one node, and every erased boundary around it stamps a view type as the node's descriptor.
/// A state write below them re-renders only an inner boundary; that must not change the descriptor, because a
/// changed descriptor replaces the subtree (new fibers, lost @State identity, lost focus in the browser).
@MainActor
struct OwnerRerenderIdentityTests {
  private struct Wrapped: ViewModifier {
    func body(content: Content) -> some View { VStack(alignment: .leading, spacing: 0) { content } }
  }

  /// A documentation-style card: a title and a preview surface whose modifiers are stacked several deep.
  private struct Surface<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("Title").accessibilityIdentifier("title")
        VStack(alignment: .leading, spacing: 14) { content }
          .frame(maxWidth: .infinity, alignment: .leading)
          .modifier(AttributeModifier(attributes: ["data-layout-root": "preview"]))
          .accessibilityIdentifier("surface")
          .modifier(Wrapped())
      }
      .id("card")
      .accessibilityIdentifier("card")
    }
  }

  private struct Lab: View {
    @State private var count = 0
    @State private var highlighted = 0
    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          Button("Increment") { count += 1 }
          Text("Count: \(count)").accessibilityIdentifier("count")
        }
        VStack(alignment: .leading, spacing: 4) {
          ForEach(0..<3, id: \.self) { index in Text(index == highlighted ? "▶ \(index)" : "\(index)") }
        }
        .focusable()
        .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, 2); return .handled }
        .accessibilityIdentifier("list")
      }
    }
  }

  private func fibers(_ tree: FiberTree) -> [String: String] {
    var found: [String: String] = [:]
    func walk(_ fiber: Fiber) {
      if let id = fiber.renderNode.attributes["data-testid"] {
        found[id] = "\(fiber.structuralID.index):\(fiber.structuralID.generation) \(fiber.renderNode.descriptor ?? "-")"
      }
      fiber.children.forEach(walk)
    }
    walk(tree.root)
    return found
  }

  private func clickIncrement(_ tree: FiberTree) {
    func find(_ node: _RenderNode) -> _RenderNode? {
      if node.events["click"] != nil { return node }
      for child in node.children { if let hit = find(child) { return hit } }
      return nil
    }
    tree.dispatch(event: "click", on: find(tree.renderNode)!)
    _ = tree.renderNode
  }

  @Test func `A state write inside nested modifiers keeps the fibers around it`() {
    let tree = FiberTree(VStack { Surface { Lab() } }, deferLazyCollections: true, startLifecycle: false)
    defer { tree._dispose() }
    tree._setRecordsPackedMutations(false)
    tree.setExternalInvalidationHandler({})
    _ = tree.renderNode
    let before = fibers(tree)
    #expect(before.keys.contains("surface") && before.keys.contains("list") && before.keys.contains("count"))

    clickIncrement(tree)

    #expect(fibers(tree) == before, "same fiber ids and the same descriptors: nothing was re-created")
  }
}
