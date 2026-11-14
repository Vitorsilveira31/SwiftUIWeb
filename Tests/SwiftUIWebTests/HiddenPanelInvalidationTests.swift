import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
import SwiftUIWeb

@Suite
@MainActor
final class HiddenPanelInvalidationTests {
  private final class Probe: @unchecked Sendable { var bodies = 0 }

  private struct Counter: View {
    let probe: Probe
    var body: some View {
      let _ = probe.bodies += 1
      return Text("counter")
    }
  }

  private func owner(named name: String, in fiber: Fiber) -> UInt64? {
    if let token = fiber.renderOwnerToken, fiber.renderNode.descriptor?.contains(name) == true { return token }
    for child in fiber.children { if let found = owner(named: name, in: child) { return found } }
    return nil
  }

  @Test
  func anOwnerInsideAnInactiveTabRendersWhenTheTabIsShownNotWhileHidden() throws {
    let probe = Probe()
    var selection = 0
    let binding = Binding<Int>(get: { selection }, set: { selection = $0 })
    func screen() -> some View {
      TabView(selection: binding) {
        Text("Other").tabItem { Text("Other") }.tag(0)
        Counter(probe: probe).tabItem { Text("Counter") }.tag(1)
      }
    }
    let tree = FiberTree(screen())
    // Show the counter once so it is mounted, then hide it again.
    selection = 1
    _ = tree.update(screen())
    selection = 0
    _ = tree.update(screen())
    let token = try #require(owner(named: "Counter", in: tree.root), "the counter owner must stay mounted")
    let hiddenBaseline = probe.bodies

    tree.root.stateStore._ownerObservationDidChange(token)
    _ = tree.renderNode
    #expect(probe.bodies == hiddenBaseline, "an invalidation inside a hidden tab must not render it")
    #expect(tree.metrics.deferredHiddenOwnerRenders == 1)

    selection = 1
    _ = tree.update(screen())
    _ = tree.renderNode
    #expect(probe.bodies > hiddenBaseline, "the deferred owner renders once its tab is shown")
  }

  private struct StatefulScreen: View {
    let probe: Probe
    @State var selection = 1
    var body: some View {
      TabView(selection: $selection) {
        Text("Other").tabItem { Text("Other") }.tag(0)
        Counter(probe: probe).tabItem { Text("Counter") }.tag(1)
      }
    }
  }

  @Test
  func aTabSwitchedByATargetedUpdateSchedulesTheOwnersDeferredWhileHidden() throws {
    let probe = Probe()
    let screen = StatefulScreen(probe: probe)
    let tree = FiberTree(screen)
    screen.selection = 0
    let token = try #require(owner(named: "Counter", in: tree.root), "the counter owner must stay mounted")

    tree.root.stateStore._ownerObservationDidChange(token)
    _ = tree.renderNode
    #expect(tree.metrics.deferredHiddenOwnerRenders == 1)

    // The selection lives in the screen's own @State, so showing the tab is a
    // targeted owner update rather than a root pass. It must hand the owner
    // deferred while hidden back to the scheduler.
    let structuralBaseline = tree.metrics.schedulerStructuralFlushes
    screen.selection = 1
    #expect(tree.metrics.schedulerStructuralFlushes == structuralBaseline)
    #expect(tree._hasPendingSubtreeInvalidation, "the deferred counter owner must be scheduled once visible")
    let bodies = probe.bodies
    _ = tree._drainSubtreeUpdates()
    #expect(probe.bodies > bodies)
    #expect(!tree._hasPendingSubtreeInvalidation)
  }
}
