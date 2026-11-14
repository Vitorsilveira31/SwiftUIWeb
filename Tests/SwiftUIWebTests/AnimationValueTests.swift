import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

/// `.animation(_:value:)` animates only the transaction in which `value` changed. The node carries the timing and a
/// generation of the value; the page animates the commit in which the generation changed and snaps every other one.
@Suite
@MainActor
final class AnimationValueTests {
  private struct Bar: View {
    let width: Double
    let label: String
    let value: Int
    var body: some View {
      Text(label)
        .frame(width: width, height: 10)
        .animation(.easeOut(duration: 0.2), value: value)
    }
  }

  private struct TwoValues: View {
    let first: Int
    let second: Int
    var body: some View {
      Text("Two")
        .animation(.linear(duration: 0.1), value: first)
        .animation(.easeIn(duration: 0.3), value: second)
    }
  }

  private struct HoverCard: View {
    @State private var hovered = false
    var body: some View {
      Text("Poster")
        .offset(y: hovered ? -3 : 0)
        .animation(.easeOut(duration: 0.2), value: hovered)
        .onHover(_assigning: _hovered)
    }
  }

  private func animated(in fiber: Fiber) -> _RenderNode? {
    if fiber.renderNode.attributes["data-animation-timing"] != nil { return fiber.renderNode }
    for child in fiber.children { if let found = animated(in: child) { return found } }
    return nil
  }

  private func trigger(in fiber: Fiber) -> Fiber? {
    if fiber.renderNode._hoverProbe != nil { return fiber }
    for child in fiber.children { if let found = trigger(in: child) { return found } }
    return nil
  }

  @Test
  func theNodeCarriesTheTimingInsteadOfAPermanentTransition() throws {
    let tree = FiberTree(Bar(width: 40, label: "A", value: 1), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    let node = try #require(animated(in: tree.root))
    #expect(node.styles["transition"] == nil)
    #expect(node.attributes["data-animation-timing"] == "200ms ease-out")
    #expect(node.attributes["data-animation-value"] == "0")
  }

  @Test
  func theGenerationAdvancesOnlyWhenTheValueChanges() throws {
    let tree = FiberTree(Bar(width: 40, label: "A", value: 1), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    // A change that is not the value (the frame, the text) keeps the generation: the page lets it snap.
    _ = tree.update(Bar(width: 80, label: "B", value: 1))
    #expect(try #require(animated(in: tree.root)).attributes["data-animation-value"] == "0")
    _ = tree.update(Bar(width: 120, label: "B", value: 2))
    #expect(try #require(animated(in: tree.root)).attributes["data-animation-value"] == "1")
    _ = tree.update(Bar(width: 120, label: "C", value: 2))
    #expect(try #require(animated(in: tree.root)).attributes["data-animation-value"] == "1")
    _ = tree.update(Bar(width: 120, label: "C", value: 1))
    #expect(try #require(animated(in: tree.root)).attributes["data-animation-value"] == "2")
  }

  @Test
  func eachModifierOnANodeKeepsItsOwnGeneration() throws {
    let tree = FiberTree(TwoValues(first: 1, second: 1), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    #expect(try #require(animated(in: tree.root)).attributes["data-animation-value"] == "0.0")
    _ = tree.update(TwoValues(first: 1, second: 2))
    #expect(try #require(animated(in: tree.root)).attributes["data-animation-value"] == "0.1")
    _ = tree.update(TwoValues(first: 2, second: 2))
    #expect(try #require(animated(in: tree.root)).attributes["data-animation-value"] == "1.1")
  }

  @Test
  func aHoverRuleEasesWithTheAuthoredTimingAndLeavesTheGenerationAlone() throws {
    let tree = FiberTree(HoverCard(), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    let fiber = try #require(trigger(in: tree.root))
    // The hovered render is speculative: it neither writes the value's history nor counts as an attribute change.
    #expect(tree._resolveHover(for: fiber))
    let rules = try #require(tree._hoverRuleChanges(acked: 0))
    #expect(rules.contains("transition:transform 200ms ease-out"), Comment(rawValue: rules))
    #expect(!rules.contains(".15s"), Comment(rawValue: rules))
    _ = tree.update(HoverCard())
    #expect(try #require(animated(in: tree.root)).attributes["data-animation-value"] == "0")
  }
}
