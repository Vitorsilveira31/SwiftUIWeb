@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// A handle to a JavaScript component registered in the page, mounted in a stable host element.
///
/// The component is named, not described by code: the page's own scripts register it with
/// `SwiftUIWebDOMComponents.define(name, factory)` (a file served from the page's origin, so the
/// page's Content-Security-Policy needs no `'unsafe-eval'`). The factory returns, now or through a
/// Promise, an object with `mount(host, root, emit, state)`, `update(instance, state)` and an
/// optional `dispose(instance)`. `state` crosses as a String: it is data the component parses
/// itself, never code.
///
/// The browser may not have the component yet when the view appears (its code can be loaded
/// lazily). The mount then waits for the definition and uses the latest `state` assigned until
/// then; removing the view first cancels it.
public class DOMView {
  /// The name the page registered the component under.
  public let component: String

  /// The component's input. Assign a new value in
  /// `DOMViewRepresentable/updateDOMView(_:context:)`; the component's `update` runs when it changed.
  public var state: String

  /// Receives each message the component posts with `emit`.
  ///
  /// Assign this in `DOMViewRepresentable/makeDOMView(context:)` and capture
  /// the coordinator there, the way a UIKit delegate is wired in
  /// `makeUIView(context:)`.
  public var onMessage: ((String) -> Void)?

  /// Names the registered component to mount and the state it starts with.
  public init(component: String, state: String = "") {
    self.component = component
    self.state = state
  }
}

@_spi(Renderer) extension DOMView: _DOMViewComponent {
  @_spi(Renderer) public func _deliverMessage(_ message: String) {
    onMessage?(message)
  }
}

/// Values supplied to a ``DOMViewRepresentable`` lifecycle callback.
public struct DOMViewRepresentableContext<Representable: DOMViewRepresentable> {
  public var coordinator: Representable.Coordinator
  public var transaction: Transaction
  public var environment: EnvironmentValues

  init(coordinator: Representable.Coordinator, transaction: Transaction, environment: EnvironmentValues) {
    self.coordinator = coordinator
    self.transaction = transaction
    self.environment = environment
  }
}

/// Creates and updates one registered JavaScript component in a stable host in the page DOM.
///
/// SwiftUIWeb invokes `makeDOMView` once when the host is mounted, invokes
/// `updateDOMView` as the represented Swift value changes, and invokes
/// `dismantleDOMView` when the host leaves the page. Each instance gets its own
/// host and ShadowRoot; the component itself runs in the page (see `DOMView`).
///
/// This protocol lives in the web module (`SwiftUIWebWeb`), not in the
/// SwiftUI-shaped surface. Apps that also build for Apple platforms guard it
/// with `#if canImport(SwiftUIWebWeb)`.
public protocol DOMViewRepresentable: View where Body == Never {
  associatedtype DOMViewType: DOMView
  associatedtype Coordinator = Void
  typealias Context = DOMViewRepresentableContext<Self>

  func makeDOMView(context: Context) -> DOMViewType
  func updateDOMView(_ view: DOMViewType, context: Context)
  static func dismantleDOMView(_ view: DOMViewType, coordinator: Coordinator)
  func makeCoordinator() -> Coordinator
}

public extension DOMViewRepresentable where Coordinator == Void {
  func makeCoordinator() -> Void {}
}

public extension DOMViewRepresentable {
  static func dismantleDOMView(_ view: DOMViewType, coordinator: Coordinator) {}

  func _render(in context: _RenderContext) -> _RenderNode {
    let descriptor = _DOMViewDescriptor(
      identity: Self.self,
      make: {
        let coordinator = makeCoordinator()
        let lifecycleContext = Context(
          coordinator: coordinator,
          transaction: Transaction(),
          environment: context.environment
        )
        return _DOMViewInstance(
          coordinator: coordinator,
          domView: makeDOMView(context: lifecycleContext)
        )
      },
      update: { instance in
        guard
          let coordinator = instance.coordinator as? Coordinator,
          let view = instance.domView as? DOMViewType
        else { return }
        updateDOMView(
          view,
          context: Context(coordinator: coordinator, transaction: Transaction(), environment: context.environment)
        )
      },
      receive: { instance, message in
        instance.domView._deliverMessage(message)
      },
      dismantle: { instance in
        guard
          let coordinator = instance.coordinator as? Coordinator,
          let view = instance.domView as? DOMViewType
        else { return }
        Self.dismantleDOMView(view, coordinator: coordinator)
      }
    )
    let node = _RenderNode.element("div")
    node.attributes["data-web-mount-key"] = _DOMViewDescriptor.mountKey
    node.attributes["data-dom-view"] = "true"
    node.descriptor = "DOMViewRepresentable"
    node._domView = descriptor
    node.events["domView"] = _EventHandler(name: "domView", action: {}, valueAction: descriptor.eventAction)
    return node
  }
}
