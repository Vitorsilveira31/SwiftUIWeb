import Testing
import Observation
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

private final class FiberCoverageAdapter: FiberRuntimeAdapter {
  var mountedRoot: _RenderNode?
  var batches: [[Mutation]] = []

  func mount(root: _RenderNode) { mountedRoot = root }
  func apply(_ mutations: [Mutation]) { batches.append(mutations) }
}

private actor FiberTaskProbe {
  private var events: Set<String> = []
  private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

  func run(_ id: String) async {
    record("start:\(id)")
    do {
      try await Task.sleep(for: .seconds(60))
    } catch {
      record("cancel:\(id)")
    }
  }

  func waitForStart(_ id: String) async { await wait(for: "start:\(id)") }
  func waitForCancellation(_ id: String) async { await wait(for: "cancel:\(id)") }
  func hasEvent(_ event: String) -> Bool { events.contains(event) }

  private func wait(for event: String) async {
    guard !events.contains(event) else { return }
    await withCheckedContinuation { continuation in
      waiters[event, default: []].append(continuation)
    }
  }

  private func record(_ event: String) {
    events.insert(event)
    waiters.removeValue(forKey: event)?.forEach { $0.resume() }
  }
}

@Observable
private final class FiberPropertyModel {
  var value = 0
}

@Observable
private final class FiberRowObservationModel: Identifiable {
  let id: Int
  var title: String
  init(_ id: Int) { self.id = id; title = "Row \(id)" }
}

@Suite
@MainActor
final class FiberRuntimeCoverageTests {
  @Test
  func rendererEntryPointsPreserveTheSemanticSnapshotAndExposeCommitMetrics() {
    let tree = FiberTree(Text("initial"), deferLazyCollections: false, startLifecycle: false)
    let adapter = FiberCoverageAdapter()

    _expectEqual(tree.root.node.htmlDescription, tree.renderNode.htmlDescription)
    _expectFalse(tree._isDisposed)
    _expectEqual(tree._runtimeDiagnostics.liveNodes, UInt64(tree._liveStructuralNodeCount))

    tree.mount(to: adapter)
    _expectTrue(adapter.mountedRoot?.htmlDescription.contains("initial") == true)

    _ = tree.reconcile(Text("first"))
    let updated = tree.update(Text("second"), to: adapter)
    let reconciled = tree.reconcile(Text("third"), to: adapter)
    _expectFalse(updated.isEmpty)
    _expectFalse(reconciled.isEmpty)
    _expectEqual(adapter.batches.count, 2)
    _expectTrue(tree.root.node.htmlDescription.contains("third"))

    let environmentCommit = tree._updateEnvironmentForRenderer(nil)
    _expectTrue(environmentCommit.recordCount >= 0)
    _expectTrue(tree.root.node.htmlDescription.contains("third"))
    _ = tree._materializeLastPackedMutations()
    tree._releaseCommitStorage()
    _expectEqual(tree._lastPackedMutations.recordCount, 0)

    tree._recordDOMOperations(-2)
    tree._recordDOMOperations(3)
    tree._recordBridgeSubmission(batches: 2, commands: 7, fallbacks: 1, indexRebuilds: 4)
    tree._recordBridgeSubmission(batches: -1, commands: -5, fallbacks: -2, indexRebuilds: -3)
    _expectEqual(tree.metrics.domOperations, 3)
    _expectEqual(tree.metrics.bridgeBatches, 2)
    _expectEqual(tree.metrics.bridgeCommands, 7)
    _expectEqual(tree.metrics.bridgeFallbackCalls, 1)
    _expectEqual(tree.metrics.bridgeIndexRebuilds, 4)

    let compatibilityTree = FiberTree(StaticHTMLFiberRenderer(), Text("compatibility"))
    _expectTrue(compatibilityTree.renderNode.htmlDescription.contains("compatibility"))
  }

  @Test
  func rendererOwnedLayoutAndSplitViewStateRoundTrip() {
    let tree = FiberTree(Text("layout"), deferLazyCollections: false, startLifecycle: false)
    tree._setRootLayoutProposal(ProposedViewSize(width: 700, height: 500))
    tree._setRootLayoutProposal(nil)

    _expectNil(tree._splitViewPositions(key: "primary"))
    tree._setSplitViewPositions(key: "primary", positions: [0.22, 0.78])
    _expectEqual(tree._splitViewPositions(key: "primary"), [0.22, 0.78])
    _expectEqual(tree._childIDs(of: tree.root), tree.root.children.map(\.structuralID))
    _expectTrue(tree.fiber(at: tree.root.identity) === tree.root)
    _expectNil(tree.fiber(at: FiberIdentity(path: [_FiberKey("missing")])))
    _expectFalse(tree._environmentChanged(to: EnvironmentValues()))
    _ = tree._updateEnvironmentForRenderer(EnvironmentValues())
  }

  @Test
  func lifecycleStartsAfterMountRestartsTasksByIDAndCancelsWhenTheOwnerLeaves() async {
    _RuntimeMemoryMetrics.start()
    defer { _RuntimeMemoryMetrics.stop() }
    var appears = 0
    var disappears = 0
    let probe = FiberTaskProbe()
    func view(taskID: String) -> some View {
      Text("lifecycle")
        .onAppear { appears += 1 }
        .onDisappear { disappears += 1 }
        .task(id: taskID) { await probe.run(taskID) }
    }
    let tree = FiberTree(view(taskID: "first"), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }

    // Metrics are recorded for the thread that renders the tree; read them
    // before the first suspension point can resume on another thread.
    _expectGreaterThan(_RuntimeMemoryMetrics.snapshot().retainedRenderNodeBytes, 0)
    _expectEqual(appears, 0)
    tree._startLifecycle()
    await probe.waitForStart("first")
    _expectEqual(appears, 1)
    _ = tree.update(view(taskID: "second"))
    await probe.waitForStart("second")
    await probe.waitForCancellation("first")
    _ = tree._hostTimelineTick()
    _ = tree.update(EmptyView())
    await probe.waitForCancellation("second")
    _expectEqual(disappears, 1)
  }

  @Test
  func taskWithoutAnIDRunsAndCancelsWithTheViewLifetime() async {
    let probe = FiberTaskProbe()
    let tree = FiberTree(
      Text("unkeyed task").task { await probe.run("unkeyed") },
      deferLazyCollections: false,
      startLifecycle: false
    )
    defer { tree._dispose() }

    tree._startLifecycle()
    await probe.waitForStart("unkeyed")
    _ = tree.update(EmptyView())
    await probe.waitForCancellation("unkeyed")
  }

  @Test
  func retainedMemorySampleCountsTaskRegistrationsWithoutAnID() {
    _RuntimeMemoryMetrics.start()
    defer { _RuntimeMemoryMetrics.stop() }

    let plain = FiberTree(Text("sample"), deferLazyCollections: false, startLifecycle: false)
    let plainBytes = _RuntimeMemoryMetrics.snapshot().retainedRenderNodeBytes
    plain._dispose()
    let withTask = FiberTree(Text("sample").task {}, deferLazyCollections: false, startLifecycle: false)
    let taskBytes = _RuntimeMemoryMetrics.snapshot().retainedRenderNodeBytes
    withTask._dispose()

    _expectGreaterThan(plainBytes, 0)
    _expectGreaterThan(taskBytes, plainBytes)
  }

  @Test
  func releasingTheLastTreeReferenceOffTheMainActorStillTearsItDown() async {
    final class TreeBox: @unchecked Sendable { var tree: FiberTree? }
    let probe = FiberTaskProbe()
    let box = TreeBox()
    box.tree = FiberTree(
      Text("released").task { await probe.run("released") },
      deferLazyCollections: false,
      startLifecycle: false
    )
    box.tree?._startLifecycle()
    await probe.waitForStart("released")

    // The isolated deinit must hop back to the main actor and dispose the
    // tree, which cancels the work it still owns.
    await Task.detached { box.tree = nil }.value
    await probe.waitForCancellation("released")
  }

  @Test
  func replacingChildIdentityRetiresLifecycleBeforeStartingTheReplacement() {
    var events: [String] = []
    func page(_ identity: Int) -> some View {
      VStack {
        Text("Loading")
          .onAppear { events.append("appear-\(identity)") }
          .onDisappear { events.append("disappear-\(identity)") }
          .id(identity)
      }
    }
    let tree = FiberTree(page(0), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    tree._startLifecycle()
    _ = tree.update(page(1))
    #expect(events == ["appear-0", "disappear-0", "appear-1"])
  }

  @Test
  func tabLifecycleRunsOnlyForTheSelectedPanelAndRestartsOnSelection() async {
    var selection = 0
    var inboxAppears = 0
    var inboxDisappears = 0
    var studioAppears = 0
    var studioDisappears = 0
    var inboxTaskID = "inbox"
    var studioTaskID = 0
    let probe = FiberTaskProbe()

    func tabs() -> some View {
      TabView(selection: Binding(get: { selection }, set: { selection = $0 })) {
        Tab("Inbox", systemImage: "circle", value: 0) {
          Text("Inbox")
            .onAppear { inboxAppears += 1 }
            .onDisappear { inboxDisappears += 1 }
            .task(id: inboxTaskID) { await probe.run(inboxTaskID) }
        }
        Tab("Studio", systemImage: "circle", value: 1) {
          Text("Studio")
            .onAppear { studioAppears += 1 }
            .onDisappear { studioDisappears += 1 }
            .task(id: studioTaskID) { await probe.run("studio-\(studioTaskID)") }
        }
      }
    }

    let tree = FiberTree(tabs(), deferLazyCollections: false, startLifecycle: false)
    tree._startLifecycle()
    await probe.waitForStart("inbox")
    #expect(inboxAppears == 1)
    #expect(inboxDisappears == 0)
    #expect(studioAppears == 0)

    // Re-rendering an inactive panel (including a task-ID change) must not
    // start work until that tab becomes visible.
    studioTaskID = 1
    _ = tree.update(tabs())
    for _ in 0..<8 { await Task.yield() }
    let initialStudioTaskStarted = await probe.hasEvent("start:studio-0")
    let updatedStudioTaskStarted = await probe.hasEvent("start:studio-1")
    let hiddenStudioTaskStarted = initialStudioTaskStarted || updatedStudioTaskStarted
    #expect(!hiddenStudioTaskStarted)
    #expect(studioAppears == 0)

    selection = 1
    _ = tree.update(tabs())
    await probe.waitForStart("studio-1")
    await probe.waitForCancellation("inbox")
    #expect(inboxDisappears == 1)
    #expect(studioAppears == 1)
    #expect(studioDisappears == 0)

    // Updates to a now-inactive tab are also dormant. Re-selecting it should
    // start the latest task ID, not the one from before it disappeared.
    inboxTaskID = "inbox-returned"
    _ = tree.update(tabs())
    let hiddenInboxTaskStarted = await probe.hasEvent("start:inbox-returned")
    #expect(!hiddenInboxTaskStarted)

    selection = 0
    _ = tree.update(tabs())
    await probe.waitForStart("inbox-returned")
    await probe.waitForCancellation("studio-1")
    #expect(studioDisappears == 1)
    #expect(inboxAppears == 2)

    tree._dispose()
    await probe.waitForCancellation("inbox-returned")
  }

  @Test
  func navigationLifecycleTracksVisibleRootAndRetainedDestinations() async {
    var path = NavigationPath()
    var rootTaskID = "root"
    var rootAppears = 0
    var rootDisappears = 0
    var detailAppears = 0
    var detailDisappears = 0
    let probe = FiberTaskProbe()

    func stack() -> some View {
      NavigationStack(path: Binding(get: { path }, set: { path = $0 })) {
        Text("Root")
          .onAppear { rootAppears += 1 }
          .onDisappear { rootDisappears += 1 }
          .task(id: rootTaskID) { await probe.run(rootTaskID) }
          .navigationDestination(for: String.self) { value in
            Text("Detail \(value)")
              .onAppear { detailAppears += 1 }
              .onDisappear { detailDisappears += 1 }
              .task { await probe.run("detail") }
          }
      }
    }

    let tree = FiberTree(stack(), deferLazyCollections: false, startLifecycle: false)
    tree._startLifecycle()
    await probe.waitForStart("root")

    path.append("settings")
    _ = tree.update(stack())
    await probe.waitForStart("detail")
    await probe.waitForCancellation("root")
    #expect(rootDisappears == 1)
    #expect(detailAppears == 1)

    // A hidden root can change task identity without restarting work. Pop
    // restores the retained root and starts only the latest task identity.
    rootTaskID = "root-restored"
    _ = tree.update(stack())
    let hiddenRootTaskStarted = await probe.hasEvent("start:root-restored")
    #expect(!hiddenRootTaskStarted)

    path.removeLast()
    _ = tree.update(stack())
    await probe.waitForStart("root-restored")
    await probe.waitForCancellation("detail")
    #expect(rootAppears == 2)
    #expect(detailDisappears == 1)

    tree._dispose()
    await probe.waitForCancellation("root-restored")
  }

  @Test
  func dispatchByNodeAndFiberIdentityCoalescesActionsIntoOneCommit() {
    final class CounterBox {
      var value = 0
    }
    struct Counter: View {
      let counter: CounterBox
      var body: some View { Button("Count \(counter.value)") { counter.value += 1 } }
    }

    let counter = CounterBox()
    let view = Counter(counter: counter)
    let tree = FiberTree(view, deferLazyCollections: false, startLifecycle: false)
    let button = tree.findNode(withEvent: "click")
    func findButtonFiber(in fiber: Fiber) -> Fiber? {
      if fiber.renderNode.events["click"] != nil { return fiber }
      for child in fiber.children {
        if let found = findButtonFiber(in: child) { return found }
      }
      return nil
    }
    guard let button, let buttonFiber = findButtonFiber(in: tree.root) else {
      return _fail("button and its Fiber should be present")
    }
    var notifications = 0
    tree.setExternalInvalidationHandler({ notifications += 1 }, deferUpdates: true)

    tree.dispatch(event: "click", on: button)
    _expectEqual(counter.value, 1)
    _ = tree.update(view)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("Count 1"))
    _expectEqual(notifications, 0, "an explicit event dispatch is committed by its host turn")

    tree.dispatch(event: "click", at: buttonFiber.identity)
    _ = tree.update(view)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("Count 2"))
    tree.performEvent { tree.dispatch(event: "not-an-event", on: button) }
    _expectEqual(counter.value, 2)

    var textValue = "before"
    let inputTree = FiberTree(TextField("Value", text: Binding(get: { textValue }, set: { textValue = $0 })))
    func findEventFiber(_ event: String, in fiber: Fiber) -> Fiber? {
      if fiber.renderNode.events[event] != nil { return fiber }
      for child in fiber.children {
        if let found = findEventFiber(event, in: child) { return found }
      }
      return nil
    }
    guard let inputFiber = findEventFiber("input", in: inputTree.root) else {
      return _fail("text field Fiber should be present")
    }
    inputTree.dispatch(event: "input", value: "after", at: inputFiber.identity)
    _expectEqual(textValue, "after")
  }

  @Test
  func leafBindingCommitsOnlyChangedValuesAndReusesCellsAfterStructuralReplacement() {
    struct BoundInput: View {
      @State var value = "before"
      var horizontal = false
      var body: some View {
        if horizontal {
          HStack { TextField("Value", text: $value) }
        } else {
          VStack { TextField("Value", text: $value) }
        }
      }
    }

    var view = BoundInput()
    let tree = FiberTree(view, deferLazyCollections: false, startLifecycle: false)
    view.value = "after"
    _expectTrue(tree._hasPendingLeafUpdates)
    let updates = tree._drainLeafUpdates()
    _expectEqual(updates.count, 1)
    _expectEqual(updates.first?.value, "after")
    _expectTrue(tree._drainLeafUpdates().isEmpty, "an empty leaf queue must be a no-op")

    // Replacing the collection's parent rebuilds the physical input Fiber at
    // the same logical path. Its Binding cell must attach to the new structural
    // generation while preserving the model's current value.
    view.horizontal = true
    _ = tree.update(view)
    view.value = "remapped"
    _expectTrue(tree._hasPendingLeafUpdates)
    let remapped = tree._drainLeafUpdates()
    _expectEqual(remapped.map(\.value), ["remapped"])

    _ = tree.update(EmptyView())
    _ = tree.update(BoundInput())
    _expectTrue(tree.root.renderNode.htmlDescription.contains("before"))
  }

  @Test
  func sharedAndStaleObservationOwnersFallBackToOneRootCommit() async {
    final class Model: ObservableObject {
      var value = 0
      func set(_ value: Int) {
        self.value = value
        objectWillChange.send()
      }
    }
    struct Child: View {
      @ObservedObject var model: Model
      var body: some View { Text("value=\(model.value)") }
    }
    struct Root: View {
      let model: Model
      var body: some View { VStack { Child(model: model); Child(model: model) } }
    }

    let model = Model()
    let tree = FiberTree(Root(model: model), deferLazyCollections: false, startLifecycle: false)
    var notifications = 0
    tree.setExternalInvalidationHandler({ notifications += 1 }, deferUpdates: true)
    model.set(2)
    await _settleObservedRefreshes()
    _expectEqual(notifications, 1)
    _expectTrue(tree._observationDiagnostics.rootFallbackPending)
    _ = tree.renderNode
    _expectTrue(tree.root.renderNode.htmlDescription.contains("value=2"))
    _expectEqual(tree.metrics.schedulerStructuralFlushes, 1)

    func findDescendantOwner(in fiber: Fiber) -> Fiber? {
      for child in fiber.children {
        if child.renderOwnerToken != nil { return child }
        if let found = findDescendantOwner(in: child) { return found }
      }
      return nil
    }
    guard let staleOwner = findDescendantOwner(in: tree.root)?.renderOwnerToken else {
      return _fail("the child view should have an observation owner")
    }
    _ = tree.update(EmptyView())
    tree.root.stateStore._ownerObservationDidChange(staleOwner)
    _expectTrue(tree._hasPendingSubtreeInvalidation)
    _expectTrue(tree._observationDiagnostics.rootFallbackPending)
    _ = tree.renderNode
    _expectEqual(tree.metrics.schedulerStructuralFlushes, 3)
  }

  @Test
  func mixedObservationAndAmbiguousAggregateInvalidationFallsBackToRoot() async {
    final class AggregateModel: ObservableObject {
      var value = 0
      func set(_ value: Int) {
        self.value = value
        objectWillChange.send()
      }
    }
    struct AggregateChild: View {
      @ObservedObject var model: AggregateModel
      var body: some View { Text("aggregate=\(model.value)") }
    }
    struct Root: View {
      let property: FiberPropertyModel
      let aggregate: AggregateModel
      var body: some View {
        VStack {
          Text("property=\(property.value)")
          AggregateChild(model: aggregate)
          AggregateChild(model: aggregate)
        }
      }
    }

    let property = FiberPropertyModel()
    let aggregate = AggregateModel()
    let tree = FiberTree(Root(property: property, aggregate: aggregate), deferLazyCollections: false, startLifecycle: false)
    var notifications = 0
    tree.setExternalInvalidationHandler({ notifications += 1 }, deferUpdates: true)

    property.value = 4
    aggregate.set(8)
    await _settleObservedRefreshes()

    _expectEqual(notifications, 1)
    _expectFalse(tree._hasPendingSubtreeInvalidation)
    _expectTrue(tree._observationDiagnostics.rootFallbackPending)
    _ = tree.renderNode
    _expectEqual(tree.metrics.schedulerStructuralFlushes, 1)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("property=4"))
    _expectTrue(tree.root.renderNode.htmlDescription.contains("aggregate=8"))
  }

  @Test
  func aggregateObjectInvalidationUsesDeferredSubtreeCommitOnSnapshot() async {
    final class Model: ObservableObject {
      var value = 0
      func set(_ value: Int) {
        self.value = value
        objectWillChange.send()
      }
    }
    struct Content: View {
      @ObservedObject var model: Model
      var body: some View { Text("aggregate=\(model.value)") }
    }

    let model = Model()
    let tree = FiberTree(Content(model: model), deferLazyCollections: false, startLifecycle: false)
    var notifications = 0
    tree.setExternalInvalidationHandler({ notifications += 1 }, deferUpdates: true)

    model.set(4)
    await _settleObservedRefreshes()
    _expectEqual(notifications, 1)
    _expectTrue(tree._hasPendingSubtreeInvalidation)
    _ = tree.renderNode

    _expectTrue(tree.root.renderNode.htmlDescription.contains("aggregate=4"))
    _expectEqual(tree.metrics.schedulerSubtreeFlushes, 1)
    _expectEqual(tree.metrics.schedulerStructuralFlushes, 0)
  }

  @Test
  func sharedAggregateObjectUsesImmediateRootCommitForSynchronousHosts() async {
    final class Model: ObservableObject {
      var value = 0
      func set(_ value: Int) {
        self.value = value
        objectWillChange.send()
      }
    }
    struct Child: View {
      @ObservedObject var model: Model
      var body: some View { Text("shared=\(model.value)") }
    }
    struct Root: View {
      let model: Model
      var body: some View { VStack { Child(model: model); Child(model: model) } }
    }

    let model = Model()
    let tree = FiberTree(Root(model: model), deferLazyCollections: false, startLifecycle: false)
    var notifications = 0
    tree.setExternalInvalidationHandler { notifications += 1 }

    model.set(8)
    await _settleObservedRefreshes()

    _expectEqual(notifications, 1)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("shared=8"))
    _expectEqual(tree.metrics.schedulerStructuralFlushes, 1)
  }

  @Test
  func subtreeDrainSubsumesNestedOwnersAndKeepsSiblingOwnersIndependent() {
    struct Leaf: View { var body: some View { Text("leaf") } }
    struct Parent: View {
      var body: some View { AnyView(VStack { AnyView(Leaf()) }) }
    }
    struct Siblings: View {
      var body: some View { HStack { AnyView(Leaf()); AnyView(Leaf()) } }
    }
    func fibers(in fiber: Fiber) -> [Fiber] {
      [fiber] + fiber.children.flatMap(fibers)
    }

    let nestedTree = FiberTree(Parent(), deferLazyCollections: false, startLifecycle: false)
    let nestedOwners = fibers(in: nestedTree.root).filter { $0.renderOwnerToken != nil }
    guard let ancestor = nestedOwners.min(by: { $0.identity.path.count < $1.identity.path.count }),
          let descendant = nestedOwners.first(where: {
            $0.identity.path.count > ancestor.identity.path.count &&
              zip(ancestor.identity.path, $0.identity.path).allSatisfy { $0 == $1 }
          }),
          let ancestorToken = ancestor.renderOwnerToken,
          let descendantToken = descendant.renderOwnerToken else {
      return _fail("expected nested retained render owners")
    }
    nestedTree.setExternalInvalidationHandler({}, deferUpdates: true)
    nestedTree.root.stateStore._ownerObservationDidChange(ancestorToken)
    nestedTree.root.stateStore._ownerObservationDidChange(descendantToken)
    let nestedEvaluations = nestedTree.metrics.bodyEvaluations
    _ = nestedTree._drainSubtreeUpdates()
    _expectEqual(nestedTree.metrics.subtreeOwnerInvalidations, 2)
    _expectEqual(nestedTree.metrics.bodyEvaluations - nestedEvaluations, 1)
    _expectTrue(nestedTree._drainSubtreeUpdates().isEmpty)

    let siblingTree = FiberTree(Siblings(), deferLazyCollections: false, startLifecycle: false)
    let siblingFibers = fibers(in: siblingTree.root).filter { $0.renderOwnerToken != nil }
    let deepestOwners = siblingFibers.filter {
      $0.identity.path.count == siblingFibers.map(\.identity.path.count).max()
    }
    guard let first = deepestOwners.first,
          let second = deepestOwners.first(where: { $0 !== first }),
          let firstToken = first.renderOwnerToken,
          let secondToken = second.renderOwnerToken else {
      return _fail("expected two sibling retained render owners")
    }
    siblingTree.setExternalInvalidationHandler({}, deferUpdates: true)
    siblingTree.root.stateStore._ownerObservationDidChange(firstToken)
    siblingTree.root.stateStore._ownerObservationDidChange(secondToken)
    _expectEqual(siblingTree._observationDiagnostics.pendingSubtreeOwners.count, 2)
    let siblingEvaluations = siblingTree.metrics.bodyEvaluations
    _ = siblingTree._drainSubtreeUpdates()
    _expectEqual(siblingTree.metrics.subtreeOwnerInvalidations, 2)
    _expectEqual(siblingTree.metrics.bodyEvaluations - siblingEvaluations, 2)
  }

  @Test
  func packedSubtreeDrainAndDisposedTreeGuardsAreSafe() {
    struct Owner: View {
      var body: some View { ForEach([0], id: \.self) { _ in Text("owned") } }
    }

    let tree = FiberTree(Owner(), deferLazyCollections: false, startLifecycle: false)
    _expectTrue(tree._materializeLazyCollection(
      ownerIdentity: tree.root.identity,
      indices: [0],
      beforeExtent: 0,
      afterExtent: 0
    ).isEmpty)
    guard let owner = tree.root.renderOwnerToken else {
      return _fail("the erased root should own its retained render closure")
    }
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    tree.root.stateStore._ownerObservationDidChange(owner)
    _expectTrue(tree._hasPendingSubtreeInvalidation)
    let packed = tree._drainPackedSubtreeUpdates()
    _expectEqual(tree.metrics.schedulerSubtreeFlushes, 1)
    _expectEqual(packed.recordCount, tree.lastMutations.count)
    _expectFalse(tree._hasPendingSubtreeInvalidation)
    _expectEqual(tree._drainPackedSubtreeUpdates().recordCount, 0)

    let snapshot = tree.renderNode
    tree._dispose()
    tree._dispose()
    _expectTrue(tree._isDisposed)
    _expectTrue(tree.renderNode === snapshot)
    _expectTrue(tree.update(Text("ignored")).isEmpty)
    _expectTrue(tree._materializeLastPackedMutations().isEmpty)
    _expectTrue(tree._lazyCollections().isEmpty)
    _expectTrue(tree._materializeLazyCollection(
      ownerIdentity: tree.root.identity,
      indices: [0],
      beforeExtent: 0,
      afterExtent: 0
    ).isEmpty)
    tree.dispatch(event: "click")
    tree.dispatch(event: "click", value: "ignored")
    tree.dispatch(event: "click", at: tree.root.identity)
    tree.dispatch(event: "input", value: "ignored", at: tree.root.identity)
    tree.performEvent { _fail("disposed trees must not execute host events") }
    tree._startLifecycle()
    tree._setRootLayoutProposal(nil)
    tree._setSplitViewPositions(key: "disposed", positions: [1])
    _expectNil(tree._splitViewPositions(key: "disposed"))
    _ = tree._hostTimelineTick()
    _ = tree._updateForRenderer(Text("ignored"))
    _ = tree._updateEnvironmentForRenderer(EnvironmentValues())
  }

  @Test
  func lazyWindowDeduplicatesIndicesAndKeepsEmptyRowsMeasurable() {
    struct LazyRows: View {
      var body: some View {
        LazyHStack { ForEach([0, 1], id: \.self) { value in Text("item \(value)") } }
      }
    }
    struct EmptyRows: View {
      var body: some View { LazyVStack { ForEach([0], id: \.self) { _ in EmptyView() } } }
    }

    let tree = FiberTree(LazyRows(), deferLazyCollections: true, startLifecycle: false)
    guard let collection = tree._lazyCollections().first else {
      return _fail("expected a deferred horizontal collection")
    }
    _ = tree._materializeLazyCollection(
      ownerIdentity: collection.ownerIdentity,
      indices: [0, 0, -1, 2, 1],
      beforeExtent: -5,
      afterExtent: 12
    )
    let html = tree.root.renderNode.htmlDescription
    _expectEqual(html.components(separatedBy: "item 0").count - 1, 1)
    _expectEqual(html.components(separatedBy: "item 1").count - 1, 1)
    func nodes(_ node: _RenderNode) -> [_RenderNode] {
      [node] + node.children.flatMap(nodes)
    }
    let spacers = nodes(tree.root.renderNode).filter { $0.attributes["data-lazy-spacer"] != nil }
    _expectEqual(spacers.count, 2)
    _expectEqual(spacers.map { $0.attributes["data-size-w"] }, ["0.0", "12.0"])
    _expectEqual(spacers.map { $0.styles["width"] }, ["0.0px", "12.0px"])

    let emptyTree = FiberTree(EmptyRows(), deferLazyCollections: true, startLifecycle: false)
    guard let emptyCollection = emptyTree._lazyCollections().first else {
      return _fail("expected a deferred empty-row collection")
    }
    _ = emptyTree._materializeLazyCollection(
      ownerIdentity: emptyCollection.ownerIdentity,
      indices: [0],
      beforeExtent: 0,
      afterExtent: 0
    )
    _expectTrue(emptyTree.root.renderNode.htmlDescription.contains("lazy-cell"))
  }

  @Test
  func lazyLayoutReportsItsConfigurationAndPreservesMeasuredItemsAcrossRemap() {
    let engine = _LazyLayoutEngine(axis: .horizontal, count: 3, estimatedExtent: 20, overscan: 5)
    _expectEqual(engine.count, 3)
    _expectEqual(engine.estimatedExtent, 20)
    _expectEqual(engine.overscan, 5)
    _expectEqual(engine.rangeChanges, 0)
    _expectEqual(engine.measuredCount, 0)
    _expectEqual(engine.measurementUpdates, 0)

    _ = engine.updateMeasured(index: 0, size: 32)
    engine.overscan = 12
    engine.remap([0, nil, 2], estimatedExtent: 24)
    _expectEqual(engine.overscan, 12)
    _expectEqual(engine.extent(at: 0), 32)
    _expectEqual(engine.extent(at: 1), 24)
    engine.remapByOffset(newCount: 2, oldOffset: 1)
    engine.setCount(1, estimatedExtent: 18)
    _expectEqual(engine.count, 1)
    _expectEqual(engine.estimatedExtent, 18)
    _expectEqual(engine.index(at: engine.offset(of: 0)), 0)
    _expectEqual(engine.plan(offset: 0, viewport: 20).range, 0..<1)
  }

  @Test
  func packedAndDOMCommandInspectionHandlesValidAndOutOfRangeReferences() {
    let command = _DOMMutationCommand(opcode: .setText, a: 4, b: 7, c: 9)
    _expectEqual(command.words, [5, 4, 7, 9])

    let tree = FiberTree(Text("before"), deferLazyCollections: false, startLifecycle: false)
    _ = tree.update(Text("after"))
    let packed = tree._lastPackedMutations
    guard let record = packed.record(at: 0) else { return _fail("expected one packed update") }
    _expectEqual(packed.node(at: record.value)?.text, "before")
    _expectEqual(packed.node(at: record.value + 1)?.text, "after")
    _expectNil(packed.node(at: _PackedMutationBuffer.noReference))
    _expectNil(packed.node(at: UInt32(packed.nodes.count)))
    _expectNil(packed.structuralID(at: _PackedMutationBuffer.noReference))
    _expectNil(packed.structuralID(at: UInt32(packed.structuralIDs.count)))
    _expectNil(packed.record(at: -1))
    _expectNil(packed.record(at: packed.recordCount))
  }

  @Test
  func observingOneForEachRowDoesNotReconcileItsSiblings() {
    struct RowView: View {
      let row: FiberRowObservationModel
      var body: some View { Text(row.title) }
    }
    struct Root: View {
      let rows: [FiberRowObservationModel]
      var body: some View {
        VStack {
          ForEach(rows, id: \.id) { row in RowView(row: row) }
        }
      }
    }

    let rows = (0..<100).map(FiberRowObservationModel.init)
    let tree = FiberTree(Root(rows: rows), deferLazyCollections: false, startLifecycle: false)
    let beforeEvaluations = tree.metrics.bodyEvaluations
    let beforeVisits = tree.metrics.reconciledNodes
    tree.setExternalInvalidationHandler({}, deferUpdates: true)

    rows[0].title = "Moved row"
    _ = tree.renderNode

    #expect(tree.root.renderNode.htmlDescription.contains("Moved row"))
    #expect(tree.metrics.bodyEvaluations - beforeEvaluations == 1)
    #expect(tree.metrics.reconciledNodes - beforeVisits < 20, "reconciled \(tree.metrics.reconciledNodes - beforeVisits) nodes for one row")
    #expect(tree.metrics.subtreeTargetPathDepthTotal > 0)
    #expect(tree.metrics.subtreeTargetRenderNodeCount < 20)

    rows[0].title = "Updated twice"
    _ = tree.renderNode
    #expect(tree.root.renderNode.htmlDescription.contains("Updated twice"), "owner routing must follow its refreshed token")
  }

  @Test
  func ownerPathsResolveToNearestMountedRenderOwnerButKeepRootFallback() {
    let root = _FiberKey("root")
    let path = [_FiberKey("app"), _FiberKey("canvas"), _FiberKey("node"), _FiberKey("content")]
    let canvas = FiberIdentity(path: [root, _FiberKey("app"), _FiberKey("canvas")])
    let exact = FiberIdentity(path: [root] + path)

    #expect(
      _nearestMountedRenderOwnerIdentity(path: path, isMountedRenderOwner: { $0 == canvas }) == canvas
    )
    #expect(
      _nearestMountedRenderOwnerIdentity(path: path, isMountedRenderOwner: { $0 == exact }) == exact
    )
    #expect(
      _nearestMountedRenderOwnerIdentity(path: path, isMountedRenderOwner: { $0 == FiberIdentity(path: [root]) }) == nil
    )
    #expect(_nearestMountedRenderOwnerIdentity(path: [], isMountedRenderOwner: { _ in true }) == nil)
  }

  @Test
  func recentlyRetiredOwnerRoutesByItsLastMountedFiberIdentity() {
    struct Owner: View {
      var body: some View { VStack { Text("stable subtree") } }
    }
    struct Root: View {
      var body: some View { VStack { AnyView(Owner()) } }
    }

    func deepestMountedOwner(in fiber: Fiber) -> Fiber? {
      let descendants = fiber.children.flatMap { child -> [Fiber] in
        [child] + descendantsOf(child)
      }
      return descendants
        .filter { $0.renderOwnerToken != nil }
        .max { $0.identity.path.count < $1.identity.path.count }
    }
    func descendantsOf(_ fiber: Fiber) -> [Fiber] {
      fiber.children.flatMap { child in [child] + descendantsOf(child) }
    }

    let tree = FiberTree(Root(), deferLazyCollections: false, startLifecycle: false)
    guard let owner = deepestMountedOwner(in: tree.root),
          let retiredToken = owner.renderOwnerToken else {
      return _fail("expected a mounted descendant render owner")
    }
    let identity = owner.identity
    tree.setExternalInvalidationHandler({}, deferUpdates: true)

    _ = tree.update(Root())
    guard let mountedReplacement = tree.fiber(at: identity),
          let activeToken = mountedReplacement.renderOwnerToken else {
      return _fail("the unchanged owner should retain its Fiber identity")
    }
    _expectNotEqual(activeToken, retiredToken)

    tree.root.stateStore._ownerObservationDidChange(retiredToken)
    let diagnostics = tree._observationDiagnostics
    #expect(diagnostics.rootFallbackPending == false, "\(diagnostics); metrics=\(tree.metrics)")
    _expectEqual(diagnostics.pendingSubtreeOwners, [activeToken])

    _ = tree.renderNode
    _expectEqual(tree.metrics.schedulerSubtreeFlushes, 1)
    _expectEqual(tree.metrics.deferredRootPasses, 0)
  }

  @Test
  func detachedOwnerTokensJoinTheNextSubtreeReplacementTransaction() {
    let store = StateStore()
    let source = _StateSourceID(rawValue: 901)
    store._beginRenderPass()
    store._dependencies.recordRead(source, owner: 11)
    store._dependencies.recordRead(source, owner: 12)
    store._endRenderPass(provenLeafSources: [])
    store._stageDependencyOwnerReplacements([11])

    store._beginSubtreeRenderPass(replacing: [12])
    store._dependencies.recordRead(source, owner: 13)
    store._endSubtreeRenderPass(provenLeafSources: [])
    store._dependencies.markDirty(source)

    #expect(store._dependencies.dirtyOwners(of: source) == [13])
  }

  @Test
  func publishedOwnerRoutingValidatesEveryDirtySourceIndependently() {
    let allReadersLive = _activePublishedObservationOwners(bySource: [
      81: [11, 12],
      82: [21]
    ]) { token in
      [11: 101, 12: 102, 21: 201][token]
    }
    #expect(allReadersLive == Set([101, 102, 201]))

    // An active owner for source 81 must not hide the fact that source 82 has
    // no mounted reader. That case needs a root correctness fallback.
    let oneSourceHasOnlyStaleReaders = _activePublishedObservationOwners(bySource: [
      81: [11],
      82: [22]
    ]) { token in
      token == 11 ? 101 : nil
    }
    #expect(oneSourceHasOnlyStaleReaders == nil)

    // Retired siblings can be pruned when the same source still has a live
    // reader; the live reader remains a valid targeted update.
    let sharedSourceHasLiveReader = _activePublishedObservationOwners(bySource: [
      81: [11, 12]
    ]) { token in
      token == 11 ? 101 : nil
    }
    #expect(sharedSourceHasLiveReader == Set([101]))

    // A changed source with no reader at all has nothing to invalidate, so it
    // must not force a root pass; readers that cannot be resolved still do.
    let unreadSourceIsIgnored = _activePublishedObservationOwners(bySource: [
      81: [11],
      82: []
    ]) { token in
      token == 11 ? 101 : nil
    }
    #expect(unreadSourceIsIgnored == Set([101]))
    #expect(_activePublishedObservationOwners(bySource: [82: []], resolve: { $0 }) == Set<UInt64>())
  }

  @Test
  func publishedOwnerRoutingClassifiesFallbackReasonsAndStaleSiblings() {
    #expect(_resolvePublishedObservationOwners(sourceCount: 1, groups: nil, resolve: { _ in nil }) == .groupsUnavailable)
    #expect(_resolvePublishedObservationOwners(sourceCount: 2, groups: [81: [11]], resolve: { $0 }) == .sourceCountMismatch)
    #expect(
      _resolvePublishedObservationOwners(sourceCount: 1, groups: [81: [11, 12]], resolve: { _ in nil })
        == .groupsWithoutActiveOwners(unresolvedOwnerTokens: 2)
    )
    #expect(
      _resolvePublishedObservationOwners(sourceCount: 1, groups: [81: [11, 12]], resolve: { $0 == 11 ? 101 : nil })
        == .routed(owners: [101], unresolvedOwnerTokens: 1)
    )
  }

  @Test
  func fiberIdentityIndexTracksRetainedInsertedAndRemovedRows() {
    struct Rows: View {
      let ids: [String]
      var body: some View { VStack { ForEach(ids, id: \.self) { Text($0) } } }
    }
    func fibers(in fiber: Fiber) -> [Fiber] { [fiber] + fiber.children.flatMap(fibers) }

    let tree = FiberTree(Rows(ids: ["a", "b", "c"]), deferLazyCollections: false, startLifecycle: false)
    let initial = fibers(in: tree.root)
    guard let retained = initial.first(where: { $0.renderNode.text == "b" }),
          let removed = initial.first(where: { $0.renderNode.text == "a" }) else {
      return _fail("expected keyed row Fibers")
    }
    let retainedIdentity = retained.identity
    let removedIdentity = removed.identity

    _ = tree.update(Rows(ids: ["b", "d"]))
    let current = fibers(in: tree.root)
    guard let inserted = current.first(where: { $0.renderNode.text == "d" }) else {
      return _fail("expected the inserted row Fiber")
    }
    #expect(tree.fiber(at: retainedIdentity) === retained)
    #expect(tree.fiber(at: inserted.identity) === inserted)
    #expect(tree.fiber(at: removedIdentity) == nil)
  }
}
