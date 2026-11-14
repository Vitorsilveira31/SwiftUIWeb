import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite(.serialized)
@MainActor
struct ConditionalLayerIdentityTests {
  private struct Counter: View {
    @State private var count = 0
    var body: some View { Button("Count \(count)") { count += 1 } }
  }
  private struct OverlayRoot: View {
    let visible: Bool
    var body: some View {
      VStack { Counter() }.overlay { if visible { Text("Layer") } }
    }
  }
  private struct BackgroundRoot: View {
    let visible: Bool
    var body: some View {
      VStack { Counter() }.background { if visible { Text("Layer") } }
    }
  }
  @Test func conditionalOverlayKeepsBaseIdentity() {
    let tree = FiberTree(OverlayRoot(visible: true))
    assertBase(tree, update: { visible in _ = tree.update(OverlayRoot(visible: visible)) })
  }
  @Test func conditionalBackgroundKeepsBaseIdentity() {
    let tree = FiberTree(BackgroundRoot(visible: true))
    assertBase(tree, update: { visible in _ = tree.update(BackgroundRoot(visible: visible)) })
  }
  private func assertBase(_ tree: FiberTree, update: (Bool) -> Void) {
    guard let initial = button(tree.root) else { Issue.record("Missing counter"); return }
    let identity = initial.identity
    tree.dispatch(event: "click", at: identity)
    _ = tree.renderNode
    for visible in [false, true, false] {
      update(visible)
      #expect(button(tree.root)?.identity == identity)
      #expect(tree.renderNode.htmlDescription.contains("Count 1"))
    }
  }
  private func button(_ fiber: Fiber) -> Fiber? {
    if fiber.renderNode.events["click"] != nil { return fiber }
    for child in fiber.children { if let value = button(child) { return value } }
    return nil
  }
}
