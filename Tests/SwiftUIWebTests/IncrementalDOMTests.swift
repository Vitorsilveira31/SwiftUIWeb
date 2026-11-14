import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(WebMount) import SwiftUIWebBrowser

@Observable private final class SemanticInvalidationModel {
  var title = "before"
}

@Suite
@MainActor
final class IncrementalDOMTests {
  @Test
  func testMountedSurfaceKeepsFiberIdentityAcrossUnrelatedStateUpdate() {
    let first = FiberTree(MountFixture(value: 0))
    guard let initial = findMount(in: first.root) else {
      return _fail("mount surface was not present in the initial Fiber tree")
    }

    let initialIdentity = initial.identity
    let mutations = first.update(MountFixture(value: 1))
    guard let retained = first.fiber(at: initialIdentity) else {
      return _fail("unrelated update removed the mounted Fiber")
    }

    _expectEqual(retained.identity, initialIdentity)
    _expectFalse(mutations.contains { mutation in
      if case .update(_, _, let fiber) = mutation { return fiber.identity == initialIdentity }
      return false
    }, "an unchanged mount should not receive a spurious update")
    _expectFalse(mutations.contains { mutation in
      if case .replace(_, _, let fiber) = mutation { return fiber.identity == initialIdentity }
      return false
    })
  }

  @Test
  func testUnmountProducesRemoveMutationForMountedSurface() {
    let tree = FiberTree(MountFixture(value: 0, includeMount: true))
    guard let mounted = findMount(in: tree.root) else {
      return _fail("mount surface was not present in the initial Fiber tree")
    }
    let identity = mounted.identity
    let mutations = tree.update(MountFixture(value: 1, includeMount: false))

    _expectNil(tree.fiber(at: identity))
    _expectTrue(mutations.contains { mutation in
      if case .remove(let node, _, _) = mutation {
        return node.attributes["data-web-mount-key"] == "test-surface"
      }
      return false
    })
  }

  @Test
  func testWebSubscriptionCancelsExactlyOnce() {
    var cancellations = 0
    let subscription = WebSubscription { cancellations += 1 }
    subscription.cancel()
    subscription.cancel()
    _expectEqual(cancellations, 1)
  }

  @Test
  func testMountSurfaceStaysSemanticOutsideBrowserHost() {
    let html = StaticHTMLFiberRenderer().render(MountFixture(value: 0))
    _expectTrue(html.contains("data-web-mount-key=\"test-surface\""))
    _expectFalse(html.contains("JSObject"))
  }

  @Test
  func testKnownBindingUsesLeafQueueWithoutReevaluatingStructure() {
    let view = BoundStateFixture()
    let tree = FiberTree(view)
    let initialBodyEvaluations = tree.metrics.bodyEvaluations
    view.value = "after"

    _expectTrue(tree._hasPendingLeafUpdates)
    let updates = tree._drainLeafUpdates()
    _expectEqual(updates.count, 1)
    _expectEqual(updates[0].value, "after")
    if case .property("value") = updates[0].operation {
      // expected operation
    } else {
      _fail("expected a direct value-property update")
    }
    _expectFalse(tree._hasPendingLeafUpdates)
    _expectEqual(tree.metrics.bodyEvaluations, initialBodyEvaluations, "a leaf commit must not evaluate the root body")
    _expectEqual(tree.metrics.schedulerInvalidations, 1)
    _expectEqual(tree.metrics.schedulerLeafFlushes, 1)
    _expectEqual(tree.metrics.bindingCellUpdates, 1)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("value=\"before\""), "semantic snapshot stays unchanged until a host commit")
  }

  @Test
  func testSemanticSnapshotDrainsKnownBindingWithoutRootReconcile() {
    let view = BoundStateFixture()
    let tree = FiberTree(view)
    let initialBodies = tree.metrics.bodyEvaluations
    let initialVisits = tree.metrics.reconciledNodes

    view.value = "snapshot update"
    let html = tree.renderNode.htmlDescription

    _expectTrue(html.contains("value=\"snapshot update\""))
    _expectEqual(tree.metrics.bodyEvaluations, initialBodies)
    _expectEqual(tree.metrics.reconciledNodes, initialVisits)
    _expectEqual(tree.metrics.schedulerLeafFlushes, 1)
    _expectEqual(tree.metrics.bindingCellUpdates, 1)
  }

  @Test
  func testDispatchingTextEditorEventCommitsLeafWithoutRootReconcile() {
    struct Editor: View {
      @State var text = "before"
      var body: some View { VStack { Text("Comment"); TextEditor(text: $text) } }
    }

    let tree = FiberTree(Editor(), deferLazyCollections: false, startLifecycle: false)
    let initialBodies = tree.metrics.bodyEvaluations
    func findInput(in fiber: Fiber) -> Fiber? {
      if fiber.renderNode.events["input"] != nil { return fiber }
      for child in fiber.children {
        if let found = findInput(in: child) { return found }
      }
      return nil
    }
    guard let input = findInput(in: tree.root) else {
      return _fail("TextEditor input Fiber should be present")
    }

    tree.dispatch(event: "input", value: "after", at: input.identity)
    let html = tree.renderNode.htmlDescription

    _expectTrue(html.contains("<textarea"))
    _expectTrue(html.contains("after"))
    func findTextarea(in node: _RenderNode) -> _RenderNode? {
      if node.kind == .element("textarea") { return node }
      for child in node.children {
        if let found = findTextarea(in: child) { return found }
      }
      return nil
    }
    let textarea = findTextarea(in: tree.renderNode)
    _expectEqual(textarea?.children.first?.text, "after", "leaf updates must change textarea text content, which backs its DOM value")
    _expectNil(textarea?.attributes["value"], "textarea values must not be represented as a value attribute")
    _expectEqual(tree.metrics.bodyEvaluations, initialBodies, "a proven TextEditor leaf event must not rebuild the root body")
    _expectEqual(tree.metrics.schedulerLeafFlushes, 1)
    _expectEqual(tree.metrics.bindingCellUpdates, 1)
  }

  @Test
  func testAmbiguousStateReadFallsBackToStructuralReconciliation() {
    let view = ConditionalBoundStateFixture()
    let tree = FiberTree(view)
    view.value = "changed"

    _expectFalse(tree._hasPendingLeafUpdates)
    let html = tree.renderNode.htmlDescription
    _expectTrue(html.contains("changed"))
  }

  @Test
  func testUnboundBindingReadFallsBackToStructuralReconciliation() {
    let view = BindingReadFixture()
    let tree = FiberTree(view)
    view.value = "changed"

    _expectFalse(tree._hasPendingLeafUpdates)
    _expectTrue(tree.renderNode.htmlDescription.contains("changed"))
  }

  @Test
  func testDynamicStyleModifierUpdatesAfterStateChange() {
    struct Styled: View {
      @State var highlighted = false
      var body: some View {
        VStack {
          Button("Toggle") { highlighted.toggle() }
          Text("probe").foregroundColor(highlighted ? .blue : .gray)
        }
      }
    }

    let view = Styled()
    let tree = FiberTree(view)
    guard let initial = findFiber(where: { $0.styles["color"] == Color.gray.cssValue }, in: tree.root) else {
      return _fail("initial dynamic style was not rendered")
    }
    tree.dispatch(event: "click")
    _ = tree.update(view)
    guard let updated = findFiber(where: { $0.styles["color"] == Color.blue.cssValue }, in: tree.root) else {
      return _fail("state-driven style was not updated")
    }
    _expectEqual(initial.identity, updated.identity, "style update should retain the logical Fiber identity")
  }

  /// Each pass registers its inner owners afresh; the previous pass's ones must leave the registry with the owners
  /// they returned a node for (they used to stay for good: a window resized for a minute held millions of bytes).
  @Test
  func testRenderingASubtreeAgainRetiresTheInnerOwnersOfThePreviousPass() {
    // Erased views that return their content's node: the inner one is an inner owner, and the Fiber carries the
    // outer one's token, not its own.
    struct OuterWrapper: View {
      let index: Int
      var body: some View { AnyView(AnyView(Text("leaf \(index)"))) }
    }
    struct WrappedRows: View {
      @State var value = 0
      var body: some View {
        VStack {
          Text("count \(value)")
          ForEach(0..<8, id: \.self) { OuterWrapper(index: $0) }
        }
      }
    }
    struct RowsHost: View {
      let rows: WrappedRows
      var body: some View { VStack { rows } }
    }
    let rows = WrappedRows()
    let tree = FiberTree(RowsHost(rows: rows))
    var invalidations = 0
    tree.setExternalInvalidationHandler({ invalidations += 1 }, deferUpdates: true)
    rows.value = 1
    _ = tree._drainSubtreeUpdates()
    let settled = tree._registeredOwnerCount
    for value in 2...20 {
      rows.value = value
      _ = tree._drainSubtreeUpdates()
    }
    _expectTrue(tree.root.renderNode.htmlDescription.contains("count 20"))
    _expectEqual(tree._registeredOwnerCount, settled)
  }

  /// A picker renders its options only to read them; owners registered for them would never reach a Fiber.
  @Test
  func testRenderingAPickerAgainLeavesNoOwnersForItsOptions() {
    struct Filters: View {
      @State var value = 0
      @State var choice = "all"
      var body: some View {
        VStack {
          Text("count \(value)")
          Picker("Filter", selection: $choice) {
            ForEach(["all", "video", "ledger"], id: \.self) { AnyView(AnyView(Text($0))).tag($0) }
          }
        }
      }
    }
    struct FiltersHost: View {
      let filters: Filters
      var body: some View { VStack { filters } }
    }
    let filters = Filters()
    let tree = FiberTree(FiltersHost(filters: filters))
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    filters.value = 1
    _ = tree.renderNode
    let settled = tree._registeredOwnerCount
    for value in 2...20 {
      filters.value = value
      _ = tree.renderNode
    }
    let html = tree.root.renderNode.htmlDescription
    _expectTrue(html.contains("count 20") && html.contains("ledger"))
    _expectEqual(tree._registeredOwnerCount, settled)
  }

  /// A tab view mounts its tabs and builds its own section headers: owners of the sections it rendered to read them
  /// would never reach a Fiber.
  @Test
  func testRenderingATabViewAgainLeavesNoOwnersForItsSections() {
    struct SectionedTabs: View {
      @State var value = 0
      @State var selected = "home"
      var body: some View {
        TabView(selection: $selected) {
          Tab("Home", systemImage: "circle", value: "home") { Text("home \(value)") }
          TabSection(content: {
            Tab("Studio", systemImage: "circle", value: "studio") { Text("studio") }
          }, header: { AnyView(AnyView(Text("Studio section"))) })
        }
      }
    }
    struct TabsHost: View {
      let tabs: SectionedTabs
      var body: some View { VStack { tabs } }
    }
    let tabs = SectionedTabs()
    let tree = FiberTree(TabsHost(tabs: tabs))
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    tabs.value = 1
    _ = tree.renderNode
    let settled = tree._registeredOwnerCount
    for value in 2...20 {
      tabs.value = value
      _ = tree.renderNode
    }
    let html = tree.root.renderNode.htmlDescription
    _expectTrue(html.contains("home 20") && html.contains("Studio section"))
    _expectEqual(tree._registeredOwnerCount, settled)
  }

  @Test
  func testStructuralInvalidationTargetsOwningSubtree() {
    final class Counters {
      var leftBodies = 0
      var rightBodies = 0
    }
    struct Child: View {
      let side: String
      let counters: Counters
      @State var value = 0
      var body: some View {
        if side == "left" { counters.leftBodies += 1 } else { counters.rightBodies += 1 }
        return Text("\(side):\(value)")
      }
    }
    struct Root: View {
      let left: Child
      let right: Child
      var body: some View { VStack { left; right } }
    }

    let counters = Counters()
    let left = Child(side: "left", counters: counters)
    let right = Child(side: "right", counters: counters)
    let root = Root(left: left, right: right)
    let tree = FiberTree(root)
    _expectEqual(counters.leftBodies, 1)
    _expectEqual(counters.rightBodies, 1)
    guard let leftFiber = findFiber(containing: "left:0", in: tree.root) else {
      return _fail("missing left retained Fiber")
    }
    let leftObject = ObjectIdentifier(leftFiber)
    var hostInvalidations = 0
    tree.setExternalInvalidationHandler({ hostInvalidations += 1 }, deferUpdates: true)

    left.value = 1
    _expectEqual(hostInvalidations, 1)
    _expectTrue(tree._hasPendingSubtreeInvalidation, "a uniquely-owned structural source should target its owner")
    let mutations = tree._drainSubtreeUpdates()
    _expectFalse(mutations.isEmpty)
    _expectEqual(counters.leftBodies, 2)
    _expectEqual(counters.rightBodies, 1, "unrelated subtree body must not be evaluated")
    _expectTrue(tree.root.renderNode.htmlDescription.contains("left:1"))
    guard let updatedLeftFiber = findFiber(containing: "left:1", in: tree.root) else {
      return _fail("missing updated left Fiber")
    }
    _expectEqual(ObjectIdentifier(updatedLeftFiber), leftObject)
    _expectEqual(tree.metrics.schedulerSubtreeFlushes, 1)
    _expectEqual(tree.metrics.subtreeOwnerInvalidations, 1)
  }

  @Test
  func testObservationDiagnosticsSubsumesNestedOwnersToMinimumSubtree() {
    struct Leaf: View {
      var body: some View { Text("leaf") }
    }
    struct Parent: View {
      var body: some View { ForEach([0], id: \.self) { _ in Leaf() } }
    }

    let tree = FiberTree(Parent())
    func collect(_ fiber: Fiber) -> [Fiber] {
      [fiber] + fiber.children.flatMap(collect)
    }
    let owners = collect(tree.root).filter { $0.renderOwnerToken != nil }
    guard let ancestor = owners.first(where: { candidate in
      owners.contains { other in
        candidate !== other && candidate.identity.path.count < other.identity.path.count &&
          zip(candidate.identity.path, other.identity.path).allSatisfy { $0 == $1 }
      }
    }), let descendant = owners.first(where: { candidate in
      candidate !== ancestor && ancestor.identity.path.count < candidate.identity.path.count &&
        zip(ancestor.identity.path, candidate.identity.path).allSatisfy { $0 == $1 }
    }), let ancestorToken = ancestor.renderOwnerToken, let descendantToken = descendant.renderOwnerToken else {
      return _fail("expected nested retained observation owners")
    }

    tree.root.stateStore._ownerObservationDidChange(ancestorToken)
    tree.root.stateStore._ownerObservationDidChange(descendantToken)

    let diagnostics = tree._observationDiagnostics
    _expectEqual(diagnostics.candidateSubtreeOwners.count, 2)
    _expectEqual(diagnostics.pendingSubtreeOwners, [ancestorToken])
    _expectEqual(diagnostics.plan, .subtree([ancestorToken]))
    _expectFalse(diagnostics.rootFallbackPending)
  }

  @Test
  func testDeferredObservationNotificationsCoalesceUntilOneCommit() {
    struct Root: View {
      var body: some View { ForEach([0], id: \.self) { _ in Text("row") } }
    }

    let tree = FiberTree(Root())
    guard let owner = tree.root.renderOwnerToken else {
      return _fail("observation root did not register an owner")
    }
    var notifications = 0
    tree.setExternalInvalidationHandler({ notifications += 1 }, deferUpdates: true)

    tree.root.stateStore._ownerObservationDidChange(owner)
    tree.root.stateStore._ownerObservationDidChange(owner)

    _expectEqual(notifications, 1)
    _expectTrue(tree._hasPendingSubtreeInvalidation)
    _ = tree.renderNode
    _expectFalse(tree._hasPendingSubtreeInvalidation)
    _expectEqual(notifications, 1)
  }

  @Test
  func testEnvironmentDependencyTargetsOwnerWhenContextHasNoLocalOverride() {
    final class Counters {
      var themedBodies = 0
      var siblingBodies = 0
    }
    struct Themed: View {
      let counters: Counters
      @Environment(\.isEnabled) private var enabled
      var body: some View {
        counters.themedBodies += 1
        return Text(enabled ? "enabled" : "disabled")
      }
    }
    struct Sibling: View {
      let counters: Counters
      var body: some View {
        counters.siblingBodies += 1
        return Text("stable")
      }
    }
    struct Root: View {
      let themed: Themed
      let sibling: Sibling
      var body: some View { VStack { themed; sibling } }
    }

    let counters = Counters()
    let themed = Themed(counters: counters)
    let sibling = Sibling(counters: counters)
    let root = Root(themed: themed, sibling: sibling)
    var environment = EnvironmentValues()
    let tree = FiberTree(root, environment: environment)
    let initialThemed = counters.themedBodies
    let initialSibling = counters.siblingBodies
    let initialOwners = tree.metrics.invalidatedOwners

    environment.isEnabled = false
    let packed = tree._updateForRenderer(root, environment: environment)

    _expectGreaterThan(packed.recordCount, 0)
    _expectEqual(counters.themedBodies, initialThemed + 1)
    _expectEqual(counters.siblingBodies, initialSibling, "unrelated owners must not reevaluate for an environment change")
    _expectTrue(tree.root.renderNode.htmlDescription.contains("disabled"))
    _expectEqual(tree.metrics.schedulerStructuralFlushes, 0)
    _expectEqual(tree.metrics.schedulerSubtreeFlushes, 1)
    _expectGreaterThan(tree.metrics.invalidatedOwners, initialOwners)
  }

  @Test
  func testEnvironmentOverrideFallsBackToRootForCorrectPropagation() {
    final class Counter { var bodies = 0 }
    struct Child: View {
      let counter: Counter
      @Environment(\.isEnabled) private var enabled
      var body: some View {
        counter.bodies += 1
        return Text(enabled ? "local-on" : "local-off")
      }
    }
    struct Root: View {
      let child: Child
      var body: some View { child.environment(\.isEnabled, true) }
    }

    let counter = Counter()
    let root = Root(child: Child(counter: counter))
    var environment = EnvironmentValues()
    // Make the root and the local override use the same numeric revision. A
    // revision-only implementation would incorrectly treat the child as an
    // inherited owner and overwrite its explicit `true` value.
    environment.isEnabled = true
    let tree = FiberTree(root, environment: environment)
    let initial = counter.bodies
    environment.isEnabled = false

    let packed = tree._updateForRenderer(root, environment: environment)
    // The local override keeps the rendered value unchanged, so a correct
    // root reconciliation may legitimately emit an empty mutation batch.
    _ = packed
    _expectEqual(counter.bodies, initial + 1)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("local-on"), "ancestor environment override must win")
    // One targeted or root pass, never both: the override must be re-applied by
    // exactly one evaluation whichever route resolves the owner.
    _expectEqual(
      tree.metrics.schedulerStructuralFlushes + tree.metrics.schedulerSubtreeFlushes, 1,
      "ambiguous environment propagation must be handled by a single pass"
    )
  }

  @Test
  func testSharedObservableObjectDependencyFallsBackToRootAndRefreshesEveryOwner() async {
    final class Model: ObservableObject {
      var value = 0
      func set(_ value: Int) {
        self.value = value
        objectWillChange.send()
      }
    }
    final class Counters {
      var first = 0
      var second = 0
    }
    struct Child: View {
      @ObservedObject var model: Model
      let increment: () -> Void
      var body: some View {
        increment()
        return Text("value=\(model.value)")
      }
    }
    struct Root: View {
      let model: Model
      let counters: Counters
      var body: some View {
        VStack {
          Child(model: model, increment: { counters.first += 1 })
          Child(model: model, increment: { counters.second += 1 })
        }
      }
    }

    let model = Model()
    let counters = Counters()
    let root = Root(model: model, counters: counters)
    let tree = FiberTree(root)
    let firstBefore = counters.first
    let secondBefore = counters.second

    model.set(4)
    await _settleObservedRefreshes()

    _expectTrue(tree.root.renderNode.htmlDescription.contains("value=4"))
    _expectGreaterThan(counters.first, firstBefore)
    _expectGreaterThan(counters.second, secondBefore)
    _expectEqual(tree.metrics.schedulerStructuralFlushes, 1,
                   "a shared aggregate model dependency must use root reconciliation")
    _expectEqual(tree.metrics.schedulerSubtreeFlushes, 0)
  }

  @Test
  func testFineGrainedAndCoarseInvalidationHaveIdenticalObservableSemantics() {
    struct Child: View {
      let model: SemanticInvalidationModel
      var body: some View { Text(model.title) }
    }
    struct Root: View {
      let model: SemanticInvalidationModel
      var body: some View { VStack { Child(model: model); Text("stable sibling") } }
    }

    let model = SemanticInvalidationModel()
    let coarse = FiberTree(Root(model: model))
    let fine = FiberTree(Root(model: model))
    model.title = "after"

    // The coarse path is the compatibility/native baseline. The browser path
    // drains the owner-scoped invalidation without rebuilding the sibling.
    _ = coarse.update(Root(model: model))
    _ = fine._drainSubtreeUpdates()

    _expectEqual(coarse.root.renderNode.htmlDescription, fine.root.renderNode.htmlDescription)
    _expectTrue(fine.root.renderNode.htmlDescription.contains("stable sibling"))
    _expectEqual(fine.metrics.schedulerStructuralFlushes, 0)
    _expectEqual(fine.metrics.schedulerSubtreeFlushes, 1)
  }

  @Test
  func testStructuralArenaReusesOnlyRemovedGenerations() {
    let tree = FiberTree(Group { Text("A") })
    let initial = tree._liveStructuralNodeCount
    _ = tree.update(Group { Text("A"); Text("B") })
    let expanded = tree._liveStructuralNodeCount
    let removedID = tree.root.children.first?.children.last?.structuralID
    _expectGreaterThan(expanded, initial)
    _ = tree.update(Group { Text("A") })
    _expectEqual(tree._liveStructuralNodeCount, initial)
    _ = tree.update(Group { Text("A"); Text("C") })
    _expectEqual(tree._liveStructuralNodeCount, expanded)
    let insertedID = tree.root.children.first?.children.last?.structuralID
    _ = tree.update(Group { Text("A") })
    _ = tree.update(Group { Text("A"); Text("D") })
    _ = tree.update(Group { Text("A") })
    _ = tree.update(Group { Text("A"); Text("E") })
    let reusedID = tree.root.children.first?.children.last?.structuralID
    if let removedID, let insertedID, let reusedID {
      _expectEqual(insertedID.index, reusedID.index, "the free list should reuse a released arena slot")
      _expectNotEqual(insertedID.generation, reusedID.generation, "reused slots must reject stale callbacks")
      _expectNotEqual(removedID, reusedID, "a stale node from an earlier removal must never alias a new child")
      _expectNotEqual(insertedID, reusedID, "all released generations remain invalid after reuse")
    }
  }

  @Test
  func testStaticTemplateRetainsRepresentationAcrossUnrelatedRefreshes() {
    let tree = FiberTree(VStack {
      Text("Static title")
      Group {
        Text("Static body")
        Text("Static footer")
      }
    })
    guard let initial = findFiber(containing: "Static body", in: tree.root) else {
      return _fail("missing static subtree")
    }
    let initialNode = ObjectIdentifier(initial.renderNode)
    let initialMutations = tree.lastMutations.count

    for _ in 0..<5 {
      let mutations = tree.update(VStack {
        Text("Static title")
        Group {
          Text("Static body")
          Text("Static footer")
        }
      })
      _expectTrue(mutations.isEmpty, "an unchanged static template should not touch the DOM")
    }

    guard let retained = findFiber(containing: "Static body", in: tree.root) else {
      return _fail("static subtree disappeared after refresh")
    }
    _expectEqual(ObjectIdentifier(retained.renderNode), initialNode)
    _expectEqual(tree.lastMutations.count, initialMutations)
    _expectGreaterThan(tree.metrics.staticTemplateReuses, 0)
    _expectGreaterThan(tree.metrics.staticTemplateHits, 0)
  }

  @Test
  func testStaticTemplateFingerprintNeverHidesChangedValue() {
    let tree = FiberTree(Text("before"))
    let initial = ObjectIdentifier(tree.root.renderNode)
    let mutations = tree.update(Text("after"))

    _expectFalse(mutations.isEmpty)
    _expectNotEqual(ObjectIdentifier(tree.root.renderNode), initial)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("after"))
  }

  @Test
  func testTrackedStateDisqualifiesStaticTemplateCandidate() {
    struct Stateful: View {
      @State var value = 1
      var body: some View { Text("value:\(value)") }
    }
    let tree = FiberTree(Stateful())
    _expectNil(tree.root.renderNode._staticTemplateKey)
  }

  @Test
  func testLazyForEachDefersRowsUntilMaterialized() {
    let view = LazyVStack {
      ForEach(Array(0..<10_000), id: \.self) { value in
        Text("Row \(value)")
      }
    }
    let tree = FiberTree(view)
    let collections = tree._lazyCollections()
    _expectEqual(collections.count, 1)
    _expectEqual(collections[0].descriptor.count, 10_000)
    _expectFalse(tree.root.renderNode.htmlDescription.contains("Row 9999"))
    _expectLessThan(tree._liveStructuralNodeCount, 20, "deferred rows must not allocate one Fiber per item")

    let mutations = tree._materializeLazyCollection(
      ownerIdentity: collections[0].ownerIdentity,
      indices: Array(0..<8),
      beforeExtent: 0,
      afterExtent: 10_000 * 64 - 8 * 64
    )
    _expectFalse(mutations.isEmpty)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("Row 0"))
    _expectFalse(tree.root.renderNode.htmlDescription.contains("Row 9999"))
  }

  @Test
  func testLazyLayoutUsesCompactPrefixIndexAndCorrectsVariableHeights() {
    let engine = _LazyLayoutEngine(axis: .vertical, count: 100_000, estimatedExtent: 50, overscan: 300)
    let initial = engine.plan(offset: 50_000 * 50, viewport: 600, velocity: 0)
    _expectLessThan(initial.range.count, 100, "a distant jump should mount only viewport plus overscan")
    _expectEqual(engine.index(at: engine.offset(of: 42)), 42)
    let measured = engine.updateMeasured(index: 10, size: 120)
    _expectTrue(measured.changed)
    _expectEqual(engine.extent(at: 10), 120)
    _expectEqual(engine.index(at: engine.offset(of: 42)), 42)
    _expectGreaterThan(engine.totalExtent, 100_000 * 50)
    _expectGreaterThan(engine.layoutQueries, 0)
    _expectGreaterThan(engine.measurementUpdates, 0)
  }

  @Test
  func testLazyUnmountRemountKeepsLogicalStateByKey() {
    struct StatefulRow: View {
      let id: Int
      @State var taps = 0
      var body: some View { Button("\(id):\(taps)") { taps += 1 } }
    }
    let view = LazyVStack { ForEach([7], id: \.self) { StatefulRow(id: $0) } }
    let tree = FiberTree(view)
    guard let info = tree._lazyCollections().first else { return _fail("missing lazy descriptor") }
    _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: [0], beforeExtent: 0, afterExtent: 0)
    _expectTrue(tree.findNode(withEvent: "click") != nil)
    tree.dispatch(event: "click")
    _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: [0], beforeExtent: 0, afterExtent: 0)
    _ = tree.update(view)
    _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: [], beforeExtent: 0, afterExtent: 0)
    _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: [0], beforeExtent: 0, afterExtent: 0)
    _expectTrue(tree.root.renderNode.htmlDescription.contains("7:1"), "logical @State must follow the keyed item, not the physical cell")
  }

  @Test
  func testLazyLogicalRemovalRetiresStateBeforeTheSameKeyReturns() {
    struct StatefulRow: View {
      let id: Int
      @State var taps = 0
      var body: some View { Button("\(id):\(taps)") { taps += 1 } }
    }
    func view(_ ids: [Int]) -> some View {
      LazyVStack { ForEach(ids, id: \.self) { StatefulRow(id: $0) } }
    }

    let tree = FiberTree(view([7]))
    guard let info = tree._lazyCollections().first else { return _fail("missing lazy descriptor") }
    _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: [0], beforeExtent: 0, afterExtent: 0)
    tree.dispatch(event: "click")
    _ = tree.update(view([]))
    _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: [], beforeExtent: 0, afterExtent: 0)
    _ = tree.update(view([7]))
    _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: [0], beforeExtent: 0, afterExtent: 0)

    _expectTrue(tree.root.renderNode.htmlDescription.contains("7:0"), "a logically removed lazy ID should receive fresh state when it returns")
  }

  private func findMount(in fiber: Fiber) -> Fiber? {
    if fiber.renderNode.attributes["data-web-mount-key"] == "test-surface" { return fiber }
    for child in fiber.children {
      if let found = findMount(in: child) { return found }
    }
    return nil
  }

  private func findFiber(containing text: String, in fiber: Fiber) -> Fiber? {
    if case .text = fiber.renderNode.kind, fiber.renderNode.htmlDescription.contains(text) { return fiber }
    for child in fiber.children {
      if let found = findFiber(containing: text, in: child) { return found }
    }
    return nil
  }

  private func findFiber(where predicate: (_RenderNode) -> Bool, in fiber: Fiber) -> Fiber? {
    if predicate(fiber.renderNode) { return fiber }
    for child in fiber.children {
      if let found = findFiber(where: predicate, in: child) { return found }
    }
    return nil
  }

}

private struct MountFixture: View {
  let value: Int
  var includeMount = true

  var body: some View {
    VStack {
      if includeMount { WebMountSurface(tag: "input", key: "test-surface") }
      Text("unrelated \(value)")
    }
  }
}

private struct BoundStateFixture: View {
  @State var value = "before"

  var body: some View {
    TextField("Value", text: $value)
  }
}

private struct ConditionalBoundStateFixture: View {
  @State var value = "before"

  var body: some View {
    if value == "before" {
      TextField("Value", text: $value)
    } else {
      Text(value)
    }
  }
}

private struct BindingReadFixture: View {
  @State var value = "before"

  var body: some View {
    BindingReadView(value: $value)
  }
}

private struct BindingReadView: View {
  let value: Binding<String>

  var body: some View {
    if value.wrappedValue == "before" {
      Text("before")
    } else {
      Text("changed")
    }
  }
}
