import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
import SwiftUIWebWeb

/// Records the owner registry and owner token a primitive view renders under,
/// so a test can reproduce races between an owner closure and its Fiber.
private final class FiberOwnerCapture {
  var registry: _RenderOwnerRegistry?
  var token: UInt64?
}

private struct FiberOwnerProbe: View {
  typealias Body = Never
  let capture: FiberOwnerCapture
  let label: String

  func _render(in context: _RenderContext) -> _RenderNode {
    capture.registry = context._renderOwnerRegistry
    capture.token = context._renderOwnerToken
    return Text(label)._render(in: context)
  }
}

/// A framework-style control that emits one leaf binding of the given kind.
private struct FiberLeafProbe: View {
  typealias Body = Never
  let tag: String
  let operation: _LeafBindingOperation
  let value: Binding<String>

  func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element(tag)
    let current = value.wrappedValue
    switch operation {
    case .textContent where tag == "textarea": node.children = [.text(current)]
    case .textContent: node.text = current
    case .style(let name): node.styles[name] = current
    case .property(let name), .attribute(let name): node.attributes[name] = current
    }
    if let sourceID = value._sourceID {
      node.leafBindings.append(_LeafBindingDescriptor(sourceID: sourceID, operation: operation, value: { value.wrappedValue }))
    }
    return node
  }
}

/// A node that is a hidden tab panel in one state and a different, visible
/// element in the other, so one reconciliation both replaces and reveals it.
private struct FiberRevealedPanel: View {
  typealias Body = Never
  let hidden: Bool
  let onAppear: @MainActor () -> Void

  func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element(hidden ? "div" : "section")
    if hidden {
      node.attributes["data-tab-panel"] = "true"
      node.attributes["data-tab-hidden"] = "true"
    }
    node.events["appear"] = _EventHandler(name: "appear", action: onAppear)
    return node
  }
}

private struct FiberMapWidget: DOMViewRepresentable {
  let label: String
  func makeDOMView(context: Context) -> DOMView { DOMView(component: "map", state: label) }
  func updateDOMView(_ view: DOMView, context: Context) {}
}

private struct FiberChartWidget: DOMViewRepresentable {
  func makeDOMView(context: Context) -> DOMView { DOMView(component: "chart") }
  func updateDOMView(_ view: DOMView, context: Context) {}
}

/// Keeps one view type at the same position while its rendered content moves
/// between DOM components and ordinary nodes.
private struct FiberWidgetSwitcher: View {
  typealias Body = Never
  let mode: Int

  func _render(in context: _RenderContext) -> _RenderNode {
    switch mode {
    case 0: FiberMapWidget(label: "first")._render(in: context)
    case 1: FiberMapWidget(label: "second")._render(in: context)
    case 2: FiberChartWidget()._render(in: context)
    default: Text("plain")._render(in: context)
    }
  }
}

@MainActor private func allFibers(in fiber: Fiber) -> [Fiber] {
  [fiber] + fiber.children.flatMap(allFibers)
}

@MainActor private func allNodes(in node: _RenderNode) -> [_RenderNode] {
  [node] + node.children.flatMap(allNodes)
}

@Suite
@MainActor
final class FiberRetainedEdgeCaseTests {
  @Test
  func structuralLivenessFollowsMountedFibersAndDisposal() throws {
    struct Rows: View {
      let showDetail: Bool
      var body: some View {
        VStack {
          Text("summary")
          if showDetail { Text("detail") }
        }
      }
    }

    let tree = FiberTree(Rows(showDetail: true), deferLazyCollections: false, startLifecycle: false)
    let detail = try #require(allFibers(in: tree.root).first { $0.renderNode.text == "detail" })
    let detailID = detail.structuralID
    #expect(tree._isStructuralNodeLive(tree.root.structuralID))
    #expect(tree._isStructuralNodeLive(detailID))

    _ = tree.update(Rows(showDetail: false))
    #expect(!tree._isStructuralNodeLive(detailID), "a removed Fiber's generation must not be reported live")
    #expect(tree._isStructuralNodeLive(tree.root.structuralID))

    tree._dispose()
    #expect(!tree._isStructuralNodeLive(tree.root.structuralID), "nothing is live once the tree is disposed")
  }

  @Test
  func snapshotAppliesTextContentAndStyleLeafUpdatesWithoutABodyPass() throws {
    struct LeafHost: View {
      @State var value = "blue"
      var body: some View {
        VStack {
          FiberLeafProbe(tag: "textarea", operation: .textContent, value: $value)
          FiberLeafProbe(tag: "output", operation: .textContent, value: $value)
          FiberLeafProbe(tag: "meter", operation: .style("color"), value: $value)
        }
      }
    }

    let view = LeafHost()
    let tree = FiberTree(view, deferLazyCollections: false, startLifecycle: false)
    let evaluations = tree.metrics.bodyEvaluations
    func node(_ tag: String) -> _RenderNode? {
      allNodes(in: tree.root.renderNode).first { $0.kind == .element(tag) }
    }

    view.value = "red"
    #expect(tree._hasPendingLeafUpdates)
    _ = tree.renderNode
    #expect(node("textarea")?.children.map(\.text) == ["red"], "a textarea's value is its text content")
    #expect(node("output")?.text == "red")
    #expect(node("meter")?.styles["color"] == "red")
    #expect(tree.metrics.bodyEvaluations == evaluations, "leaf-only writes must not re-evaluate a body")
    #expect(!tree._hasPendingLeafUpdates)

    view.value = ""
    _ = tree.renderNode
    #expect(node("meter")?.styles["color"] == nil, "an empty style value removes the declaration")
    #expect(node("output")?.text == "")
  }

  @Test
  func snapshotDefersALeafWriteToAPendingObservationPass() throws {
    struct Form: View {
      @State var name = "before"
      var body: some View { VStack { TextField("Name", text: $name) } }
    }

    let view = Form()
    let tree = FiberTree(view, deferLazyCollections: false, startLifecycle: false)
    let owner = try #require(tree.root.renderOwnerToken)
    view.name = "after"
    #expect(tree._hasPendingLeafUpdates)

    // An Observation change for the same owner arrives before the snapshot.
    // The leaf fast path must give way to the structural pass, which renders
    // the current value itself.
    tree.root.stateStore._ownerObservationDidChange(owner)
    #expect(!tree._hasPendingLeafUpdates)
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("after"), Comment(rawValue: html))
    #expect(tree.metrics.bindingCellUpdates == 0)
  }

  @Test
  func aLeafWriteWhoseControlWasRemovedInTheSameTurnProducesNoDirectUpdate() {
    struct Form: View {
      @State var name = "before"
      @State var showField = true
      var body: some View {
        VStack {
          if showField { TextField("Name", text: $name) }
          Text("form")
        }
      }
    }

    let view = Form()
    let tree = FiberTree(view, deferLazyCollections: false, startLifecycle: false)
    view.name = "after"
    #expect(tree._hasPendingLeafUpdates)
    view.showField = false
    #expect(!tree.root.renderNode.htmlDescription.contains("<input"))
    // The leaf source is still dirty, but its only cell left with the field.
    #expect(tree._drainLeafUpdates().isEmpty)
    #expect(!tree._hasPendingLeafUpdates)
  }

  @Test
  func aStateWriteFromADisappearCallbackIsCommittedAfterTheCurrentPass() {
    struct Root: View {
      @State var removals = 0
      @State var showChild = true
      var body: some View {
        VStack {
          Text("removals=\(removals)")
          if showChild {
            Text("child").onDisappear { removals += 1 }
          }
        }
      }
    }

    let view = Root()
    let tree = FiberTree(view, deferLazyCollections: false, startLifecycle: false)
    tree._startLifecycle()
    view.showChild = false
    #expect(tree.metrics.nestedChangeRootFallbacks == 1, "a write during reconciliation must be deferred, not nested")
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("removals=1"), Comment(rawValue: html))
    #expect(!html.contains("child"))
    #expect(tree.metrics.deferredRootPasses == 1)
  }

  @Test
  func timelineTickReevaluatesOnlyTheNearestRetainedOwner() {
    final class Counter { var clockBodies = 0; var siblingBodies = 0 }
    struct Clock: View {
      let counter: Counter
      var body: some View {
        counter.clockBodies += 1
        // The timeline sits below a plain container, so the tick has to walk
        // up from the timeline's own Fiber to find the retained owner.
        return VStack {
          TimelineView(.periodic(from: .init(timeIntervalSince1970: 0), by: 1)) { _ in Text("tick") }
        }
      }
    }
    struct Sibling: View {
      let counter: Counter
      var body: some View {
        counter.siblingBodies += 1
        return Text("static")
      }
    }
    struct Root: View {
      let counter: Counter
      var body: some View { VStack { Clock(counter: counter); Sibling(counter: counter) } }
    }

    let counter = Counter()
    let tree = FiberTree(Root(counter: counter), deferLazyCollections: false, startLifecycle: false)
    let clockBodies = counter.clockBodies
    let siblingBodies = counter.siblingBodies

    _ = tree._hostTimelineTick()
    #expect(tree.metrics.schedulerSubtreeFlushes == 1)
    #expect(tree.metrics.schedulerStructuralFlushes == 0)
    #expect(counter.clockBodies == clockBodies + 1)
    #expect(counter.siblingBodies == siblingBodies, "a tick must not re-evaluate views outside the timeline's owner")
  }

  @Test
  func timelineTickWithoutAnyRetainedOwnerFallsBackToTheRoot() {
    let tree = FiberTree(
      TimelineView(.periodic(from: .init(timeIntervalSince1970: 0), by: 1)) { _ in Text("tick") },
      deferLazyCollections: false,
      startLifecycle: false
    )
    let structural = tree.metrics.schedulerStructuralFlushes
    let subtree = tree.metrics.schedulerSubtreeFlushes
    _ = tree._hostTimelineTick()
    #expect(tree.metrics.schedulerStructuralFlushes + tree.metrics.schedulerSubtreeFlushes == structural + subtree + 1)
    #expect(tree.root.renderNode.htmlDescription.contains("tick"))
  }

  @Test
  func environmentChangeWithALocalOverrideElsewhereUsesOneRootPass() {
    struct Themed: View {
      @Environment(\.isEnabled) private var enabled
      var body: some View { Text(enabled ? "enabled" : "disabled") }
    }
    struct Pinned: View {
      @Environment(\.isEnabled) private var enabled
      var body: some View { Text(enabled ? "pinned-on" : "pinned-off") }
    }
    struct Root: View {
      var body: some View {
        VStack {
          Themed()
          VStack { Pinned(); Text("override scope") }.environment(\.isEnabled, true)
        }
      }
    }

    var environment = EnvironmentValues()
    let tree = FiberTree(Root(), environment: environment)
    environment.isEnabled = false
    _ = tree._updateEnvironmentForRenderer(environment)

    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("disabled") && html.contains("pinned-on"), Comment(rawValue: html))
    #expect(tree.metrics.schedulerStructuralFlushes == 1, "an override anywhere makes targeted rebinding unsafe")
    #expect(tree.metrics.schedulerSubtreeFlushes == 0)
  }

  @Test
  func anOwnerWhoseClosureWasRetiredFallsBackToOneRootPass() throws {
    struct Leaf: View {
      let capture: FiberOwnerCapture
      var body: some View { FiberOwnerProbe(capture: capture, label: "leaf") }
    }
    struct Root: View {
      let capture: FiberOwnerCapture
      var body: some View { VStack { Leaf(capture: capture); Text("sibling") } }
    }

    let capture = FiberOwnerCapture()
    let tree = FiberTree(Root(capture: capture), deferLazyCollections: false, startLifecycle: false)
    let registry = try #require(capture.registry)
    let token = try #require(capture.token)
    #expect(allFibers(in: tree.root).contains { $0.renderOwnerToken == token })

    // The Fiber still carries the token, but its render closure is gone: the
    // race between a structural replacement and an Observation callback.
    registry._remove(token)
    tree.setExternalInvalidationHandler({}, deferUpdates: true)
    tree.root.stateStore._ownerObservationDidChange(token)
    _ = tree.renderNode

    #expect(tree.metrics.staleSubtreeRendererFallbacks == 1)
    #expect(tree.metrics.schedulerStructuralFlushes == 1)
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("leaf") && html.contains("sibling"), Comment(rawValue: html))
  }

  @Test
  func aRemovedOwnerRoutesToItsNearestMountedAncestorOwner() throws {
    struct Leaf: View {
      var body: some View { Text("leaf") }
    }
    struct Middle: View {
      let show: Bool
      var body: some View {
        VStack {
          if show { Leaf() }
          Text("middle")
        }
      }
    }
    struct Root: View {
      let show: Bool
      var body: some View { VStack { AnyView(Middle(show: show)) } }
    }

    let tree = FiberTree(Root(show: true), deferLazyCollections: false, startLifecycle: false)
    let leaf = try #require(allFibers(in: tree.root).first { $0.renderNode.descriptor?.contains("Leaf") == true })
    let leafToken = try #require(leaf.renderOwnerToken)
    tree.setExternalInvalidationHandler({}, deferUpdates: true)

    _ = tree.update(Root(show: false))
    let middle = try #require(allFibers(in: tree.root).first { $0.renderOwnerToken != nil && $0 !== tree.root }, "the erased Middle boundary must stay mounted")
    let middleToken = try #require(middle.renderOwnerToken)
    #expect(tree.fiber(at: leaf.identity) == nil)

    tree.root.stateStore._ownerObservationDidChange(leafToken)
    let diagnostics = tree._observationDiagnostics
    #expect(diagnostics.rootFallbackPending == false, "\(diagnostics)")
    #expect(diagnostics.pendingSubtreeOwners == [middleToken])
    _ = tree.renderNode
    #expect(tree.metrics.schedulerSubtreeFlushes == 1)
  }

  @Test
  func anInnerOwnerTokenRetiredByARootPassRoutesThroughItsRegistryPath() throws {
    struct Inner: View {
      let capture: FiberOwnerCapture
      var body: some View { FiberOwnerProbe(capture: capture, label: "inner") }
    }
    struct Outer: View {
      let capture: FiberOwnerCapture
      var body: some View { AnyView(Inner(capture: capture)) }
    }
    struct Root: View {
      let capture: FiberOwnerCapture
      var body: some View {
        HStack {
          VStack { Outer(capture: capture); Text("sibling") }
          Text("trailing")
        }
      }
    }

    let capture = FiberOwnerCapture()
    let tree = FiberTree(Root(capture: capture), deferLazyCollections: false, startLifecycle: false)
    let innerToken = try #require(capture.token)
    #expect(!allFibers(in: tree.root).contains { $0.renderOwnerToken == innerToken }, "the node carries the outer token")
    tree.setExternalInvalidationHandler({}, deferUpdates: true)

    _ = tree.update(Root(capture: capture))
    // The inner token was never a Fiber's own token and the root pass dropped
    // its outer-owner link, so only the registry's retired path can route it.
    tree.root.stateStore._ownerObservationDidChange(innerToken)
    let diagnostics = tree._observationDiagnostics
    #expect(diagnostics.rootFallbackPending == false, "\(diagnostics)")
    let outer = try #require(allFibers(in: tree.root).first { $0.renderNode.descriptor?.contains("Outer") == true })
    let routed = try #require(diagnostics.pendingSubtreeOwners.first)
    let routedFiber = try #require(allFibers(in: tree.root).first { $0.renderOwnerToken == routed })
    #expect(routedFiber !== tree.root)
    #expect(Array(outer.identity.path.prefix(routedFiber.identity.path.count)) == routedFiber.identity.path,
            "the route must target a mounted ancestor of the retired owner")
    _ = tree.renderNode
    let html = tree.root.renderNode.htmlDescription
    #expect(html.contains("inner") && html.contains("sibling"), Comment(rawValue: html))
  }

  @Test
  func aPanelRevealedByAReplacementStartsItsLifecycleOnce() {
    var appears = 0
    func screen(hidden: Bool) -> some View {
      VStack { FiberRevealedPanel(hidden: hidden, onAppear: { appears += 1 }) }
    }

    let tree = FiberTree(screen(hidden: true), deferLazyCollections: false, startLifecycle: false)
    tree._startLifecycle()
    #expect(appears == 0, "a hidden panel must not appear")
    _ = tree.update(screen(hidden: false))
    #expect(appears == 1)
    #expect(tree.root.renderNode.htmlDescription.contains("<section"))
  }

  @Test
  func domComponentsKeepTheirInstanceOnlyWhileTheRepresentableTypeIsUnchanged() throws {
    func domNode(in tree: FiberTree) -> _RenderNode? {
      allFibers(in: tree.root).map(\.renderNode).first { $0._domView != nil }
    }

    let tree = FiberTree(VStack { FiberWidgetSwitcher(mode: 0) }, deferLazyCollections: false, startLifecycle: false)
    let first = try #require(domNode(in: tree)?._domView)
    let instance = first.makeInstance()

    _ = tree.update(VStack { FiberWidgetSwitcher(mode: 1) })
    let second = try #require(domNode(in: tree)?._domView)
    #expect(second !== first, "each render produces a fresh descriptor")
    #expect(second.currentInstance === instance, "the mounted instance survives a re-render of the same type")

    _ = tree.update(VStack { FiberWidgetSwitcher(mode: 2) })
    let chart = try #require(domNode(in: tree)?._domView)
    #expect(!chart.hasSameType(as: first))
    #expect(chart.currentInstance == nil, "a different representable must not adopt another type's instance")

    _ = tree.update(VStack { FiberWidgetSwitcher(mode: 3) })
    #expect(domNode(in: tree) == nil)
    #expect(tree.root.renderNode.htmlDescription.contains("plain"))
  }
}
