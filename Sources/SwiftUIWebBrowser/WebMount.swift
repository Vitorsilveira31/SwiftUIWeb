import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

import SwiftUIWebBrowserIO

/// Internal browser mounting SPI.
///
/// The types in this file are intentionally hidden behind Swift's SPI
/// mechanism. A normal SwiftUI-compatible application never needs to know
/// that a view is backed by a DOM element or a JavaScript controller; browser
/// packages that wrap a Web library may opt in with
/// `@_spi(WebMount) import SwiftUIWebBrowser`.
@_spi(WebMount)
public struct WebElementHandle: Equatable {
  let embeddedElement: BrowserDOMElement

  fileprivate init(embeddedElement: BrowserDOMElement) { self.embeddedElement = embeddedElement }

  /// The underlying browser object for SPI WebMount implementations. This is
  /// deliberately unavailable to ordinary SwiftUIWeb applications; optional
  /// packages such as SwiftUIWebMapKit use it to hand an opaque element to a
  /// JavaScript library while keeping JavaScript out of SwiftUIWebCore.
  @_spi(WebMount)
  public var _javascriptObject: Never { fatalError("JavaScript object unavailable on this host") }

  public static func == (lhs: WebElementHandle, rhs: WebElementHandle) -> Bool {
    return lhs.embeddedElement == rhs.embeddedElement
  }

  /// Whether the element is still attached to the current document.
  public var isConnected: Bool {
    return BrowserDOMBridge.isConnected(embeddedElement)
  }

  /// Reads a DOM attribute without exposing the underlying JavaScript object.
  public func attribute(_ name: String) -> String? {
    return BrowserDOMBridge.attribute(name, of: embeddedElement)
  }

  /// Sets a DOM attribute. This is an escape hatch for a Web package's
  /// implementation and is not part of the regular SwiftUI-facing API. An event
  /// handler (`onclick`), `srcdoc` or a `javascript:` URL is refused: a value
  /// that came from data must not become script on the page.
  public func setAttribute(_ name: String, _ value: String) {
    guard let safe = _safeMountedAttributeValue(name: name, value: value) else { return }
    BrowserDOMBridge.setAttribute(name, value: safe, on: embeddedElement)
  }

  public func removeAttribute(_ name: String) {
    BrowserDOMBridge.removeAttribute(name, from: embeddedElement)
  }

  /// The live value property used by native form controls. Reading and
  /// writing the property (rather than the HTML attribute) preserves browser
  /// input state and selection across unrelated Fiber commits.
  public var value: String? {
    get {
      return BrowserDOMBridge.value(of: embeddedElement)
    }
    nonmutating set {
      BrowserDOMBridge.setValue(newValue ?? "", on: embeddedElement)
    }
  }

  public var textContent: String? {
    get {
      return BrowserDOMBridge.textContent(of: embeddedElement)
    }
    nonmutating set {
      BrowserDOMBridge.setTextContent(newValue ?? "", on: embeddedElement)
    }
  }

  fileprivate func isSameNode(as other: WebElementHandle) -> Bool { BrowserDOMBridge.isSameNode(embeddedElement, other.embeddedElement) }
}

/// A cancellation token owned by a Web mount controller. Controllers should
/// retain subscriptions and cancel them from `unmount`/`dispose`; the token
/// also cancels automatically when it is released.
@_spi(WebMount)
@MainActor public final class WebSubscription {
  private var cancellation: (() -> Void)?

  public init(_ cancellation: @escaping () -> Void) {
    self.cancellation = cancellation
    _RuntimeMemoryMetrics.recordWebSubscriptionInit()
  }

  public func cancel() {
    guard let cancellation else { return }
    self.cancellation = nil
    cancellation()
  }

  isolated deinit {
    _RuntimeMemoryMetrics.recordWebSubscriptionDeinit()
    cancel()
  }
}

/// Lifecycle owned by one stable Fiber mount token. A controller may wrap a
/// JavaScript library, a browser API, or a small native DOM enhancement.
@_spi(WebMount)
@MainActor public protocol WebMountController: AnyObject {
  func mount(element: WebElementHandle, token: String)
  func update(element: WebElementHandle, token: String)
  func unmount()
  func dispose()
}

public extension WebMountController {
  /// `unmount` is the normal lifecycle callback; `dispose` is a final hook
  /// for controllers that own subscriptions or library instances. Keeping the
  /// default empty avoids invoking an idempotency requirement on wrappers.
  func dispose() {}
}

/// A browser-only registry of implementation controllers. Registration is by
/// a semantic key emitted by `WebMountSurface`; each rendered Fiber instance
/// receives its own stable token and controller instance.
@_spi(WebMount)
@MainActor public final class WebMountRegistry {
  public static let shared = WebMountRegistry()

  public typealias Factory = (WebElementHandle, String) -> WebMountController

  private struct ActiveMount {
    let key: String
    let handle: WebElementHandle
    let controller: WebMountController
  }

  private var factories: [String: Factory] = .init()
  #if arch(wasm32)
  private var active: [String: ActiveMount] = .init()
  /// Mount tokens already reported as unimplemented, so each is reported once.
  private var reportedTokens: Set<String> = []
  #endif

  private init() {}

  /// Registers (or replaces) the implementation for a semantic mount key.
  /// The returned token can be used to remove the registration during teardown.
  @discardableResult
  public func register(key: String, factory: @escaping Factory) -> WebSubscription {
    factories[key] = factory
    return WebSubscription {
      let registry = WebMountRegistry.shared
      guard registry.factories[key] != nil else { return }
      registry.factories.removeValue(forKey: key)
    }
  }

  /// Idempotently disposes one active mount. The browser committer normally
  /// invokes this through `reconcile`, while wrappers may use it when a page
  /// or feature is torn down independently of Fiber.
  public func dispose(token: String) {
    #if arch(wasm32)
    guard let mount = active.removeValue(forKey: token) else { return }
    mount.controller.unmount()
    mount.controller.dispose()
    _RuntimeMemoryMetrics.recordWebMounts(active.count)
    #else
    _ = token
    #endif
  }

  #if arch(wasm32) && hasFeature(Embedded)
  /// Reconciles the post-commit DOM through the compact BrowserIO host. This is
  /// called only after the JavaScript patcher has applied the latest snapshot.
  public func reconcileEmbedded(changedTokens: Set<String> = []) {
    let mounts: [BrowserDOMMount]
    do { mounts = try BrowserDOMBridge.mounts() }
    catch {
      BrowserDOMBridge.report("WebMount reconciliation could not read the mounted elements: \(error.message)")
      return
    }
    var current: [String: WebElementHandle] = .init()
    var keys: [String: String] = .init()
    for mount in mounts where !mount.token.isEmpty {
      current[mount.token] = WebElementHandle(embeddedElement: mount.element)
      keys[mount.token] = mount.key
    }
    for token in active.keys where current[token] == nil { dispose(token: token) }
    reportedTokens.formIntersection(current.keys)
    for (token, handle) in current {
      guard let key = keys[token], let factory = factories[key] else {
        if reportedTokens.insert(token).inserted {
          BrowserDOMBridge.report("No WebMount implementation is registered for key \(keys[token] ?? "")", on: handle.embeddedElement)
        }
        continue
      }
      if let existing = active[token] {
        if !existing.handle.isSameNode(as: handle) {
          dispose(token: token); let controller=factory(handle,token); controller.mount(element: handle, token: token)
          active[token]=ActiveMount(key:key,handle:handle,controller:controller)
        } else if changedTokens.isEmpty || changedTokens.contains(token) {
          existing.controller.update(element: handle, token: token)
        }
      } else {
        let controller=factory(handle,token); controller.mount(element: handle, token: token)
        active[token]=ActiveMount(key:key,handle:handle,controller:controller)
      }
    }
    _RuntimeMemoryMetrics.recordWebMounts(active.count)
  }
  #endif

}

/// An internal, semantic marker for a DOM mount. It renders as an ordinary
/// HTML element in the Fiber tree and therefore does not add DOM/JavaScript
/// concepts to SwiftUIWebCore. Web packages use it behind the WebMount SPI.
@_spi(WebMount)
public struct WebMountSurface: View {
  public typealias Body = Never

  public let tag: String
  public let key: String

  public init(tag: String = "div", key: String) {
    self.tag = tag
    self.key = key
  }

  public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element(tag)
    node.attributes["data-web-mount-key"] = key
    return node
  }
}

/// A browser-neutral buffered range returned by the media mount SPI.  The
/// AVFoundation wrapper converts this value to `CMTimeRange`; ordinary
/// applications never see the browser representation.
@_spi(WebMount)
public struct WebMediaTimeRange: Hashable, Sendable {
  public let start: Double
  public let end: Double

  public init(start: Double, end: Double) {
    self.start = start
    self.end = end
  }
}

/// The small imperative media surface used by feature wrappers.  Keeping
/// these operations on the opaque handle means the public AVFoundation
/// facade never exposes DOM, JavaScript interop, or HTML types.
@_spi(WebMount)
@MainActor public extension WebElementHandle {
  var mediaCurrentTime: Double {
    get {
      return BrowserMediaBridge.currentTime(embeddedElement)
    }
    nonmutating set {
      BrowserMediaBridge.setCurrentTime(newValue, embeddedElement)
    }
  }

  var mediaDuration: Double {
    return BrowserMediaBridge.duration(embeddedElement)
  }

  var mediaRate: Double {
    get {
      return BrowserMediaBridge.rate(embeddedElement)
    }
    nonmutating set {
      BrowserMediaBridge.setRate(newValue, embeddedElement)
    }
  }

  var mediaVolume: Double {
    get {
      return BrowserMediaBridge.volume(embeddedElement)
    }
    nonmutating set {
      BrowserMediaBridge.setVolume(newValue, embeddedElement)
    }
  }

  var mediaMuted: Bool {
    get {
      return BrowserMediaBridge.muted(embeddedElement)
    }
    nonmutating set {
      BrowserMediaBridge.setMuted(newValue, embeddedElement)
    }
  }

  /// HTMLMediaElement.readyState (0 through 4).
  var mediaReadyState: Int {
    return BrowserMediaBridge.readyState(embeddedElement)
  }

  /// HTMLMediaElement.networkState (0 through 3).
  var mediaNetworkState: Int {
    return BrowserMediaBridge.networkState(embeddedElement)
  }

  var mediaBufferedRanges: [WebMediaTimeRange] {
    return BrowserMediaBridge.buffered(embeddedElement).map { WebMediaTimeRange(start: $0.0, end: $0.1) }
  }

  var mediaSeekableRanges: [WebMediaTimeRange] {
    return BrowserMediaBridge.seekable(embeddedElement).map { WebMediaTimeRange(start: $0.0, end: $0.1) }
  }

  func mediaPlay() {
    BrowserMediaBridge.play(embeddedElement)
  }

  func mediaPause() {
    BrowserMediaBridge.pause(embeddedElement)
  }

  /// Reassigns the source and asks the browser to load it.  This is used only
  /// for an already-mounted element when an AVPlayerItem is replaced.
  func mediaSetSource(_ source: String) {
    guard _isSafeMountedURL(source) else { return }
    BrowserMediaBridge.setSource(source, embeddedElement)
  }

  /// Requests the private adaptive-streaming facade.  The facade is lazy and
  /// is not touched for ordinary MP4, WebM, or audio URLs.
  func mediaAttachAdaptiveSource(_ source: String) {
    guard _isSafeMountedURL(source) else { return }
    BrowserMediaBridge.attachAdaptive(source, embeddedElement)
  }

  /// Releases a lazily-created adaptive player before a media mount is
  /// removed. Native HTML playback has no extra resource to release, while
  /// the private Shaka facade disposes its instance through this hook.
  func mediaDetachAdaptiveSource() {
    BrowserMediaBridge.detachAdaptive(embeddedElement)
  }

  /// Reports whether the browser can play a MIME type natively.  Feature
  /// wrappers use this to keep Safari's native HLS path ahead of Shaka.
  func mediaCanPlay(_ mimeType: String) -> Bool {
    return BrowserMediaBridge.canPlay(mimeType, embeddedElement)
  }

  /// Requests native fullscreen for the media element when the browser
  /// exposes the Fullscreen API.  The operation is intentionally fire and
  /// forget: browser permission/user-gesture policy decides whether it can be
  /// fulfilled, while the Swift-facing media API remains synchronous.
  func mediaRequestFullscreen() {
    BrowserMediaBridge.requestFullscreen(embeddedElement)
  }

  func mediaExitFullscreen() {
    BrowserMediaBridge.exitFullscreen(embeddedElement)
  }

  /// Starts/stops browser Picture in Picture where supported.  Safari's
  /// older prefixed presentation mode is retained as a fallback.
  func mediaSetPictureInPicture(_ enabled: Bool) {
    BrowserMediaBridge.setPictureInPicture(enabled, embeddedElement)
  }

  var mediaSupportsPictureInPicture: Bool {
    return BrowserMediaBridge.supportsPictureInPicture(embeddedElement)
  }

  /// Installs a keydown listener used by AVKit's opt-in keyboard controls.
  /// The event object is reduced to stable scalar values before crossing the
  /// SPI boundary, keeping JavaScript/DOM types private to this module.
  func mediaAddKeydownListener(_ handler: @escaping (String, Bool) -> Void) -> WebSubscription {
    let operation = BrowserMediaBridge.observeKeydown(embeddedElement, handler)
    return WebSubscription { operation.cancel() }
  }

  /// Installs a browser event listener and owns it through a cancellable
  /// WebSubscription. The JavaScript closure is retained by the subscription
  /// for as long as the media controller remains mounted.
  func mediaAddEventListener(_ event: String, _ handler: @escaping () -> Void) -> WebSubscription {
    let operation = BrowserMediaBridge.observe(embeddedElement, event: event, handler)
    return WebSubscription { operation.cancel() }
  }
}
