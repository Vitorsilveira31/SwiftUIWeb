import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// The leaf-binding scheduler on its own: a coalesced source write reaches the drain once while its owner is live,
/// and a cell whose owner the structural arena has released is dropped and counted as stale.
@Suite
@MainActor
final class FiberBindingRuntimeTests {
  @Test
  func drainEmitsALiveOwnersChangeAndCountsAReleasedOwnerAsStale() {
    let store = StateStore()
    let arena = StructuralArena()
    let runtime = BindingRuntime(store: store)
    let source = _StateSourceID(rawValue: 7)
    var text = "before"

    let node = _RenderNode.element("input")
    node.leafBindings.append(_LeafBindingDescriptor(sourceID: source, operation: .property("value"), value: { text }))
    let owner = Fiber(
      identity: FiberIdentity(path: [_FiberKey("root")]),
      node: node,
      parent: nil,
      stateStore: store,
      structuralID: arena.allocate(),
      version: 1
    )
    runtime.sync(root: owner)
    #expect(!runtime.hasDirtyLeaf, "nothing is dirty before a write")

    // A live owner: the write reaches the drain once, carrying the new value.
    text = "after"
    store._publishedObservationDidChange(source)
    #expect(runtime.hasDirtyLeaf)
    let updates = runtime.drain(arena: arena)
    #expect(updates.count == 1)
    #expect(updates.first?.value == "after")
    #expect(updates.first?.structuralID == owner.structuralID)
    #expect(updates.first?.fiberIdentity == owner.identity)
    #expect(runtime.staleGenerationSkips == 0)

    // The owner is released before the next write is drained. No sync has run, so the cell is still registered;
    // the drain must drop it, emit nothing, and count it as a stale generation.
    text = "later"
    store._publishedObservationDidChange(source)
    arena.release(owner.structuralID)
    #expect(runtime.drain(arena: arena).isEmpty)
    #expect(runtime.staleGenerationSkips == 1)
  }
}
