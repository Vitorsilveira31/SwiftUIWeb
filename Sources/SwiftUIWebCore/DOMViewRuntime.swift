/// What a browser DOM component exposes to the browser mount adapter: the name
/// of a component the page registered and the state string it renders. The
/// public DOM component type lives in `SwiftUIWebWeb`; Core only retains the
/// renderer-facing lifecycle plumbing below.
@_spi(Renderer) public protocol _DOMViewComponent: AnyObject {
  var component: String { get }
  var state: String { get }
  /// Delivers one message the component posted with `emit` to its owner.
  func _deliverMessage(_ message: String)
}

/// One retained lifecycle value for a descriptor's current Fiber identity.
@_spi(Renderer) public final class _DOMViewInstance {
  public let coordinator: Any
  public let domView: any _DOMViewComponent

  public init(coordinator: Any, domView: any _DOMViewComponent) {
    self.coordinator = coordinator
    self.domView = domView
  }
}

/// Type-erased operations consumed by the browser mount adapter.
@_spi(Renderer) public final class _DOMViewDescriptor {
  public static let mountKey = "dom-view-mount"

  public let identity: Any.Type
  private let makeOperation: () -> _DOMViewInstance
  private let updateOperation: (_DOMViewInstance) -> Void
  private let receiveOperation: (_DOMViewInstance, String) -> Void
  private let dismantleOperation: (_DOMViewInstance) -> Void
  private final class InstanceBox {
    var value: _DOMViewInstance?
  }
  private let instanceBox = InstanceBox()

  public init(
    identity: Any.Type,
    make: @escaping () -> _DOMViewInstance,
    update: @escaping (_DOMViewInstance) -> Void,
    receive: @escaping (_DOMViewInstance, String) -> Void,
    dismantle: @escaping (_DOMViewInstance) -> Void
  ) {
    self.identity = identity
    makeOperation = make
    updateOperation = update
    receiveOperation = receive
    dismantleOperation = dismantle
  }

  public func adoptState(from previous: _DOMViewDescriptor) {
    guard hasSameType(as: previous) else { return }
    instanceBox.value = previous.instanceBox.value
  }

  public func hasSameType(as other: _DOMViewDescriptor) -> Bool {
    identity == other.identity
  }

  public func makeInstance() -> _DOMViewInstance {
    let value = makeOperation()
    instanceBox.value = value
    return value
  }

  public func updateInstance() {
    guard let instance = instanceBox.value else { return }
    updateOperation(instance)
  }

  @MainActor public var eventAction: @MainActor (String) -> Void {
    let box = instanceBox
    let receive = receiveOperation
    return { message in
      guard let instance = box.value else { return }
      receive(instance, message)
    }
  }

  public func dismantleInstance() {
    guard let instance = instanceBox.value else { return }
    dismantleOperation(instance)
    instanceBox.value = nil
  }

  public var currentInstance: _DOMViewInstance? { instanceBox.value }
}
