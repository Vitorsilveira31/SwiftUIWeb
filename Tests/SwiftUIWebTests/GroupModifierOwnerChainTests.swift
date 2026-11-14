import Observation
import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A modifier applied to a `Group` with one child is a modifier on that child. A targeted re-render of the child
/// (a GeometryReader measurement, drained as a subtree update like the browser does) updates it in place: the
/// same fiber stays mounted, so its `.task` is not restarted and the state below it survives.
@Suite(.serialized)
@MainActor
struct GroupModifierOwnerChainTests {
  final class Probe { var taskStarts = 0 }

  @MainActor @Observable final class Model { var value = 0 }

  private struct Inner: View {
    let probe: Probe
    let model: Model
    var body: some View {
      GeometryReader { geometry in
        Text("n:\(model.value) w:\(Int(geometry.size.width))")
      }
      .task { probe.taskStarts += 1 }
    }
  }

  private struct FramedGroup: View {
    let probe: Probe
    let model: Model
    var body: some View {
      Group { Inner(probe: probe, model: model) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private struct PaddedGroup: View {
    let probe: Probe
    let model: Model
    var body: some View {
      Group { Inner(probe: probe, model: model) }
        .padding(8)
        .background(Color.black)
    }
  }

  private func run<V: View>(_ make: (Probe, Model) -> V) async throws {
    let probe = Probe()
    let model = Model()
    let tree = FiberTree(make(probe, model), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    tree._startLifecycle()
    for _ in 0 ..< 50 { await Task.yield() }
    let before = try #require(findFiber(containing: "w:0", in: tree.root))
    #expect(probe.taskStarts == 1)
    tree.setExternalInvalidationHandler({}, deferUpdates: true)

    // The browser reports the reader's measured size; the reader's owner is re-rendered as a subtree update.
    tree.dispatch(event: "geometry", value: "800,600")
    _ = tree._drainSubtreeUpdates()
    for _ in 0 ..< 20 { await Task.yield() }

    let after = try #require(findFiber(containing: "w:800", in: tree.root))
    #expect(ObjectIdentifier(after) == ObjectIdentifier(before))
    #expect(probe.taskStarts == 1)
  }

  @Test func targetedUpdateInsideAFramedGroupKeepsTheChildMounted() async throws {
    try await run { FramedGroup(probe: $0, model: $1) }
  }

  @Test func targetedUpdateInsideAPaddedGroupKeepsTheChildMounted() async throws {
    try await run { PaddedGroup(probe: $0, model: $1) }
  }

  private func findFiber(containing text: String, in fiber: Fiber) -> Fiber? {
    for child in fiber.children {
      if let found = findFiber(containing: text, in: child) { return found }
    }
    return fiber.renderNode.htmlDescription.contains(text) && fiber.children.allSatisfy({ !$0.renderNode.htmlDescription.contains(text) })
      ? fiber : nil
  }
}
