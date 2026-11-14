import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
struct RuntimePrimitiveTests {
  @Test
  func runtimeCapabilitiesDescribeTheNativeCoreBoundary() {
    #expect(SwiftUIWebRuntime.platform == .native)
    #expect(!SwiftUIWebRuntime.isEmbedded)
    #expect(SwiftUIWebRuntime.capabilities.isEmpty)

    #expect(SwiftUIWebRuntimeCapabilities.browserDOM.rawValue == 1)
    #expect(SwiftUIWebRuntimeCapabilities.browserEvents.rawValue == 2)
    #expect(
      (SwiftUIWebRuntimeCapabilities.browserDOM.union(.history)).rawValue == 5
    )
    #expect(
      !SwiftUIWebRuntimeCapabilities(rawValue: 0x8000)
        .contains(.browserDOM)
    )
  }

  @Test
  func scrollIdentityUsesRootAndNestedRenderPaths() {
    let root = _ScrollNode.id(for: _RenderContext(), kind: "list")
    #expect(root.rawValue == "list:root")
    #expect(root.description == "list:root")

    let nestedContext = _RenderContext(
      path: [_FiberKey("root"), _FiberKey("row")]
    )
    let nested = _ScrollNode.id(for: nestedContext, kind: "list")
    // A nested path is named by a short hash (the path text is as long as the depth).
    #expect(nested.rawValue.hasPrefix("list:") && nested.rawValue != "list:root/row")
    #expect(nested.rawValue.count <= 24)
    #expect(_ScrollNode.id(for: nestedContext, kind: "list") == nested)
    #expect(nested != root)

    let integer = _ScrollID(42)
    #expect(integer.rawValue == "42")
    #expect(_ScrollID(rawValue: integer.rawValue) == integer)
  }

  @Test
  func scrollNodeApplyPublishesStableRendererMetadata() {
    let node = _RenderNode.element("section")
    let scroll = _ScrollNode(
      id: _ScrollID(rawValue: "feed:root/items"),
      axes: [.horizontal, .vertical]
    )

    scroll.apply(to: node)

    #expect(node.kind == .element("section"))
    #expect(node.attributes["data-scroll-node"] == "true")
    #expect(node.attributes["data-scroll-id"] == "feed:root/items")
    #expect(node.attributes["data-scroll-axes"] == "3")
    #expect(node.attributes["data-layout-kind"] == "scroll")
  }

  @Test
  func fiberIdentityAndLeafUpdatesPreserveRendererContracts() {
    let identity = FiberIdentity(path: [_FiberKey("root"), _FiberKey("row")])
    #expect(identity.description == "root/row")
    #expect(FiberIdentity(path: identity.path) == identity)

    let structuralID = StructuralNodeID(index: 7, generation: 3)
    #expect(structuralID.index == 7)
    #expect(structuralID.generation == 3)

    let update = _LeafUpdate(
      fiberIdentity: identity,
      structuralID: structuralID,
      operation: .attribute("aria-label"),
      value: "Row"
    )
    #expect(update.fiberIdentity == identity)
    #expect(update.structuralID == structuralID)
    #expect(update.operation == .attribute("aria-label"))
    #expect(update.value == "Row")
  }

  @Test
  func lazyCollectionInfoKeepsOwnerContainerAndNormalizedDescriptor() {
    let descriptor = _LazyCollectionDescriptor(
      count: -2,
      axis: .horizontal,
      estimatedExtent: 0,
      laneCount: 0,
      itemType: "Row",
      spacerTag: "li",
      spacerColumnCount: 0,
      keyAt: { _FiberKey("item-\($0)") },
      renderItem: { _, _ in _RenderNode.text("row") }
    )
    let owner = FiberIdentity(path: [_FiberKey("list")])
    let container = FiberIdentity(path: [_FiberKey("list"), _FiberKey("body")])
    let info = _LazyCollectionInfo(
      ownerIdentity: owner,
      containerIdentity: container,
      descriptor: descriptor
    )

    #expect(info.ownerIdentity == owner)
    #expect(info.containerIdentity == container)
    #expect(info.descriptor.count == 0)
    #expect(info.descriptor.estimatedExtent == 1)
    #expect(info.descriptor.laneCount == 1)
    #expect(info.descriptor.spacerColumnCount == 1)
    #expect(info.descriptor.keyAt(4) == _FiberKey("item-4"))
    #expect(info.descriptor.renderItem(0, _RenderContext()).text == "row")
  }

  @Test
  func observationDiagnosticsSelectNoneSubtreeAndRootPlans() {
    let empty = _StateStoreObservationDiagnostics()
    #expect(empty.plan == .none)
    #expect(_FiberObservationDiagnostics(stateStore: empty).plan == .none)

    let targetedDependencies = _DependencyDiagnostics(
      hasDirtyStructural: true,
      hasObservation: true,
      uniqueStructuralOwners: [7],
      observationOwners: [11]
    )
    let targetedState = _StateStoreObservationDiagnostics(dependencies: targetedDependencies)
    #expect(targetedState.plan == .subtree([7, 11]))
    #expect(
      _FiberObservationDiagnostics(
        stateStore: targetedState,
        pendingSubtreeOwners: [13]
      ).plan == .subtree([13])
    )

    let rootDependencies = _DependencyDiagnostics(
      hasDirtyStructural: true,
      hasObservation: false,
      uniqueStructuralOwners: nil,
      observationOwners: []
    )
    let rootState = _StateStoreObservationDiagnostics(
      isDisposed: true,
      dependencies: rootDependencies
    )
    let rootDiagnostics = _FiberObservationDiagnostics(
      stateStore: rootState,
      rootFallbackPending: true,
      disposed: true
    )
    #expect(rootState.plan == .root)
    #expect(rootDiagnostics.plan == .root)
    #expect(rootDiagnostics.disposed)
    #expect(rootDiagnostics.stateStore.isDisposed)
  }
}
