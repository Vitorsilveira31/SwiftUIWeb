import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
import SwiftUIWebBrowserIO

private final class _DOMViewMountController: WebMountController {
  private let token: String
  private var element: WebElementHandle?
  private var descriptor: _DOMViewDescriptor?
  private var mounted = false
  private var sentState = ""

  init(token: String) {
    self.token = token
  }

  // A missing descriptor is not an error here: the host can still show a
  // snapshot that a newer Swift publication has already removed, because the
  // main thread reconciles the DOM it has, which may lag the worker. That newer
  // publication commits and reconciles again, which disposes this mount, so the
  // mount is simply left alone until then.
  func mount(element: WebElementHandle, token: String) {
    _ = token
    self.element = element
    guard let descriptor = _DOMViewRuntime.descriptor(for: self.token) else { return }
    mount(descriptor, on: element)
  }

  func update(element: WebElementHandle, token: String) {
    _ = token
    self.element = element
    guard let next = _DOMViewRuntime.descriptor(for: self.token) else { return }
    guard let current = descriptor, current.hasSameType(as: next) else {
      unmount()
      mount(next, on: element)
      return
    }
    descriptor = next
    next.updateInstance()
    // The state is the component's only input, so an unchanged one is not sent across the host boundary.
    guard let state = next.currentInstance?.domView.state, state != sentState else { return }
    sentState = state
    BrowserDOMBridge.domViewUpdate(state: state, on: element.embeddedElement)
  }

  func unmount() {
    guard mounted else { return }
    if let element, let current = descriptor {
      current.dismantleInstance()
      BrowserDOMBridge.domViewUnmount(on: element.embeddedElement)
    }
    descriptor = nil
    mounted = false
  }

  func dispose() {
    unmount()
    element = nil
  }

  private func mount(_ descriptor: _DOMViewDescriptor, on element: WebElementHandle) {
    self.descriptor = descriptor
    let instance = descriptor.makeInstance()
    sentState = instance.domView.state
    BrowserDOMBridge.domViewMount(component: instance.domView.component, state: sentState, on: element.embeddedElement)
    mounted = true
  }
}

/// Browser-side association between a stable Fiber token and its latest
/// type-erased lifecycle descriptor.
enum _DOMViewRuntime {
  @MainActor private static var descriptors: [String: _DOMViewDescriptor] = [:]
  @MainActor private static var stagedTokens: Set<String> = []
  @MainActor private static var registration: WebSubscription?

  @MainActor static func install() {
    guard registration == nil else { return }
    registration = WebMountRegistry.shared.register(key: _DOMViewDescriptor.mountKey) { _, token in
      _DOMViewMountController(token: token)
    }
  }

  @MainActor static func beginSnapshot() {
    stagedTokens.removeAll(keepingCapacity: true)
  }

  @MainActor static func stage(token: String, descriptor: _DOMViewDescriptor) {
    stagedTokens.insert(token)
    descriptors[token] = descriptor
  }

  @MainActor static func finishSnapshot() {
    for token in Array(descriptors.keys) where !stagedTokens.contains(token) {
      descriptors.removeValue(forKey: token)
    }
  }

  @MainActor static func descriptor(for token: String) -> _DOMViewDescriptor? {
    descriptors[token]
  }
}
