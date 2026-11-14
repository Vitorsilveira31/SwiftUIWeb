import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
import SwiftUIWebWeb

/// The DOMViewRepresentable lifecycle as the browser mount drives it: the descriptor a render produces makes one
/// DOMView instance, updates it, delivers its messages to the owner and dismantles it.
@Suite
@MainActor
final class DOMViewRepresentableTests {
  /// Records what the protocol requirements received, in the order the mount calls them.
  final class Recorder {
    var made = 0
    var coordinatorsOnUpdate: [Int] = []
    var dismantledCoordinators: [Int] = []
  }

  struct Counting: DOMViewRepresentable {
    typealias Coordinator = Int
    let recorder: Recorder

    func makeCoordinator() -> Int { 42 }

    func makeDOMView(context: Context) -> DOMView {
      recorder.made += 1
      return DOMView(component: "counting", state: "initial")
    }

    func updateDOMView(_ view: DOMView, context: Context) {
      recorder.coordinatorsOnUpdate.append(context.coordinator)
      view.state = "update-\(context.coordinator)"
    }

    static func dismantleDOMView(_ view: DOMView, coordinator: Int) {
      _ = view
      // Dismantling is the owner's Swift-side cleanup; the page disposes the component itself.
    }
  }

  /// Keeps the protocol's default `dismantleDOMView` and `makeCoordinator`.
  struct Plain: DOMViewRepresentable {
    func makeDOMView(context: Context) -> DOMView { DOMView(component: "plain") }
    func updateDOMView(_ view: DOMView, context: Context) {}
  }

  @Test
  func aDOMViewNamesItsComponentAndKeepsTheLatestState() {
    let view = DOMView(component: "stage")
    _expectEqual(view.component, "stage")
    _expectEqual(view.state, "")
    let described = DOMView(component: "stage", state: "{\"a\":1}")
    _expectEqual(described.state, "{\"a\":1}")
    described.state = "first"
    described.state = "second"
    _expectEqual(described.state, "second")
    _expectEqual(described.component, "stage")
  }

  @Test
  func messagesReachTheOwnerOnlyOnceACallbackIsSet() {
    let view = DOMView(component: "stage")
    var received: [String] = []
    view._deliverMessage("dropped")
    _expectEqual(received, [])
    view.onMessage = { received.append($0) }
    view._deliverMessage("kept")
    _expectEqual(received, ["kept"])
  }

  @Test
  func theMountDrivesMakeUpdateMessageAndDismantleThroughTheDescriptor() throws {
    let recorder = Recorder()
    let tree = FiberTree(Counting(recorder: recorder), deferLazyCollections: false, startLifecycle: false)
    let descriptor = try #require(tree.renderNode._domView)

    let madeBefore = recorder.made
    descriptor.makeInstance()
    _expectEqual(recorder.made, madeBefore + 1)
    let instance = try #require(descriptor.currentInstance)
    let view = try #require(instance.domView as? DOMView)
    _expectEqual(view.component, "counting")
    _expectEqual(view.state, "initial")

    // The update closure hands the live view and the coordinator the instance was made with.
    descriptor.updateInstance()
    _expectEqual(recorder.coordinatorsOnUpdate, [42])
    _expectEqual(view.state, "update-42")

    // A message the component posts reaches the owner through the tree's "domView" event.
    var delivered: [String] = []
    view.onMessage = { delivered.append($0) }
    let node = tree.findNode(withEvent: "domView")
    tree.dispatch(event: "domView", value: "ping", on: node)
    _expectEqual(delivered, ["ping"])
    // An event without a value runs only the node's no-op action.
    tree.dispatch(event: "domView", on: node)
    _expectEqual(delivered, ["ping"])

    // Dismantling forgets the instance; messages posted afterwards go nowhere.
    descriptor.dismantleInstance()
    _expectNil(descriptor.currentInstance)
    tree.dispatch(event: "domView", value: "late", on: node)
    _expectEqual(delivered, ["ping"])
  }

  @Test
  func theDefaultDismantleHookLeavesTheComponentUntouched() throws {
    let tree = FiberTree(Plain(), deferLazyCollections: false, startLifecycle: false)
    let descriptor = try #require(tree.renderNode._domView)
    descriptor.makeInstance()
    let view = try #require(descriptor.currentInstance?.domView as? DOMView)
    descriptor.dismantleInstance()
    _expectEqual(view.component, "plain")
    _expectEqual(view.state, "")
    _expectNil(descriptor.currentInstance)
  }
}
