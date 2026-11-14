@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebTransferable

/// Compatibility spelling for the URL value used by the former Core-level
/// WebView placeholder. It intentionally lives in this web module now.
public typealias SwiftUIWebWebURL = URL

/// A browser-backed source for ``WebContentView``.
///
/// This value deliberately contains no DOM, iframe, or JavaScript types. The
/// browser adapter realizes the source as an iframe and is subject to the
/// browser's normal navigation and same-origin rules.
public enum WebContent: Hashable, Sendable {
  case url(URL)
  case html(String, baseURL: URL?)

  public static func html(_ html: String) -> WebContent {
    .html(html, baseURL: nil)
  }

  public var url: URL? {
    switch self {
    case .url(let value): return value
    case .html(_, let baseURL): return baseURL
    }
  }
}

public enum WebContentLoadState: String, Hashable, Sendable {
  case idle
  case loading
  case loaded
  case failed
}

/// An error reported by the host while creating or loading web content.
///
/// An iframe does not expose HTTP response details to its parent page. In
/// particular, a cross-origin HTTP error page generally still produces a
/// successful iframe `load` event. ``WebContentError`` therefore describes
/// only errors the host can actually observe (for example, a blocked frame or
/// a browser load error), and never invents status codes.
public struct WebContentError: Error, Hashable, Sendable, CustomStringConvertible {
  public let message: String
  public let code: Int?
  public let url: URL?

  public init(message: String, code: Int? = nil, url: URL? = nil) {
    self.message = message
    self.code = code
    self.url = url
  }

  public var description: String { message }
}

public struct WebNavigationState: Hashable, Sendable {
  public var url: URL?
  public var title: String?
  public var loadState: WebContentLoadState
  public var canGoBack: Bool
  public var canGoForward: Bool
  public var error: WebContentError?

  public init(
    url: URL? = nil,
    title: String? = nil,
    loadState: WebContentLoadState = .idle,
    canGoBack: Bool = false,
    canGoForward: Bool = false,
    error: WebContentError? = nil
  ) {
    self.url = url
    self.title = title
    self.loadState = loadState
    self.canGoBack = canGoBack
    self.canGoForward = canGoForward
    self.error = error
  }

  public var isLoading: Bool { loadState == .loading }
}

public enum WebNavigationKind: String, Hashable, Sendable {
  case initial
  case urlRequest
  case html
  case link
  case backForward
  case reload
}

public struct WebNavigation: Hashable, Sendable {
  public let url: URL?
  public let kind: WebNavigationKind
  public let isMainFrame: Bool
  public let isSameOrigin: Bool

  public init(
    url: URL?,
    kind: WebNavigationKind,
    isMainFrame: Bool = true,
    isSameOrigin: Bool = false
  ) {
    self.url = url
    self.kind = kind
    self.isMainFrame = isMainFrame
    self.isSameOrigin = isSameOrigin
  }
}

public enum WebExternalLinkBehavior: String, Hashable, Sendable {
  /// Let a link navigate inside the iframe.
  case allowInWebContent
  /// Open a link in the top-level browser context.
  case openExternally
  /// Prevent the link from navigating.
  case cancel

  // Short spellings make configuration pleasant without hiding the explicit
  // browser meaning from callers.
  public static let allow = WebExternalLinkBehavior.allowInWebContent
  public static let deny = WebExternalLinkBehavior.cancel
}

public struct WebContentConfiguration: Hashable, Sendable {
  public var title: String
  public var externalLinkBehavior: WebExternalLinkBehavior

  public init(
    title: String = "Web content",
    externalLinkBehavior: WebExternalLinkBehavior = .allowInWebContent
  ) {
    self.title = title
    self.externalLinkBehavior = externalLinkBehavior
  }
}

/// Owns the source and browser navigation commands for a web content view.
///
/// Calling ``reload()``, ``goBack()``, or ``goForward()`` requests the
/// corresponding iframe operation. The browser adapter performs the operation
/// through the iframe's browsing context; the model does not pretend that a
/// cross-origin document can be inspected from Swift.
public final class WebContentModel: ObservableObject {
  public private(set) var navigationState: WebNavigationState

  public private(set) var content: WebContent

  private var commandSequence: UInt64 = 0
  private var pendingCommand: String?
  private var pendingKind: WebNavigationKind = .initial

  public init(_ content: WebContent) {
    self.content = content
    self.navigationState = WebNavigationState(url: content.url)
  }

  public convenience init(url: URL) { self.init(.url(url)) }

  public convenience init(url string: String) {
    self.init(.url(_webContentURL(string)))
  }

  public convenience init(html: String, baseURL: URL? = nil) {
    self.init(.html(html, baseURL: baseURL))
  }

  public var url: URL? { navigationState.url }
  public var isLoading: Bool { navigationState.isLoading }
  public var canGoBack: Bool { navigationState.canGoBack }
  public var canGoForward: Bool { navigationState.canGoForward }
  public var error: WebContentError? { navigationState.error }

  public func load(_ content: WebContent) {
    self.content = content
    pendingCommand = nil
    switch content {
    case .url:
      pendingKind = .urlRequest
    case .html:
      pendingKind = .html
    }
    navigationState = WebNavigationState(url: content.url, loadState: .loading)
  }

  public func load(_ url: URL) { load(.url(url)) }

  public func load(_ string: String) { load(.url(_webContentURL(string))) }

  public func loadHTML(_ html: String, baseURL: URL? = nil) {
    load(.html(html, baseURL: baseURL))
  }

  /// WebKit-compatible spelling for callers that already use
  /// `loadHTMLString(_:baseURL:)` on native platforms. In the browser the base URL must be on the app's own origin: the
  /// page's Content-Security-Policy (`base-uri 'self'`, which keeps an injected `<base>` from redirecting the app's own
  /// relative URLs) applies to inline HTML too, so the browser ignores a base on another origin, and relative URLs then
  /// resolve against the app.
  public func loadHTMLString(_ html: String, baseURL: URL? = nil) {
    loadHTML(html, baseURL: baseURL)
  }

  public func reload() {
    request(.reload)
  }

  public func goBack() {
    request(.backForward, command: "back")
  }

  public func goForward() {
    request(.backForward, command: "forward")
  }

  /// Updates history availability when a host can determine it safely. The
  /// browser adapter intentionally leaves these values unchanged when the
  /// iframe is cross-origin, because the browser forbids reading that state.
  public func updateHistoryAvailability(canGoBack: Bool, canGoForward: Bool) {
    var state = navigationState
    state.canGoBack = canGoBack
    state.canGoForward = canGoForward
    navigationState = state
  }

  private func request(_ kind: WebNavigationKind, command: String? = nil) {
    commandSequence &+= 1
    pendingCommand = String(commandSequence) + ":" + (command ?? kind.rawValue)
    pendingKind = kind
    var state = navigationState
    state.error = nil
    state.loadState = .loading
    navigationState = state
  }

  // MARK: Renderer-facing event transitions

  func _consumeCommand() -> String? {
    pendingCommand
  }

  func _navigationKind() -> WebNavigationKind { pendingKind }

  func _didFinishLoading(url: URL?) {
    pendingCommand = nil
    var state = navigationState
    state.url = url ?? state.url
    state.loadState = .loaded
    state.error = nil
    navigationState = state
  }

  func _didFailLoading(message: String, url: URL?) {
    pendingCommand = nil
    var state = navigationState
    state.url = url ?? state.url
    state.loadState = .failed
    state.error = WebContentError(message: message, url: state.url)
    navigationState = state
  }

  func _didNavigate(to url: URL, sameOrigin _: Bool) {
    pendingCommand = nil
    var state = navigationState
    state.url = url
    state.loadState = .loaded
    state.error = nil
    navigationState = state
  }
}

/// A SwiftUI-shaped web content view. Its implementation is intentionally
/// only an iframe descriptor; browser realization lives in SwiftUIWebBrowser.
public struct WebContentView: View {
  public typealias Body = Never

  @StateObject private var model: WebContentModel
  private var configuration: WebContentConfiguration
  private var onNavigation: ((WebNavigation) -> Void)?
  private var onExternalLink: ((URL) -> Void)?
  private var onError: ((WebContentError) -> Void)?

  public init(
    _ content: WebContent,
    configuration: WebContentConfiguration = WebContentConfiguration(),
    onNavigation: ((WebNavigation) -> Void)? = nil,
    onExternalLink: ((URL) -> Void)? = nil
  ) {
    _model = StateObject(wrappedValue: WebContentModel(content))
    self.configuration = configuration
    self.onNavigation = onNavigation
    self.onExternalLink = onExternalLink
    self.onError = nil
  }

  public init(
    source: WebContent,
    configuration: WebContentConfiguration = WebContentConfiguration(),
    onNavigation: ((WebNavigation) -> Void)? = nil,
    onExternalLink: ((URL) -> Void)? = nil
  ) {
    self.init(
      source,
      configuration: configuration,
      onNavigation: onNavigation,
      onExternalLink: onExternalLink
    )
  }

  public init(
    model: WebContentModel,
    configuration: WebContentConfiguration = WebContentConfiguration(),
    onNavigation: ((WebNavigation) -> Void)? = nil,
    onExternalLink: ((URL) -> Void)? = nil
  ) {
    _model = StateObject(wrappedValue: model)
    self.configuration = configuration
    self.onNavigation = onNavigation
    self.onExternalLink = onExternalLink
    self.onError = nil
  }

  public init(
    url: URL,
    title: String? = nil,
    externalLinkBehavior: WebExternalLinkBehavior = .allowInWebContent,
    onNavigation: ((WebNavigation) -> Void)? = nil,
    onExternalLink: ((URL) -> Void)? = nil
  ) {
    self.init(
      .url(url),
      configuration: WebContentConfiguration(title: title ?? "Web content", externalLinkBehavior: externalLinkBehavior),
      onNavigation: onNavigation,
      onExternalLink: onExternalLink
    )
  }

  public init(
    _ url: URL,
    title: String? = nil,
    externalLinkBehavior: WebExternalLinkBehavior = .allowInWebContent,
    onNavigation: ((WebNavigation) -> Void)? = nil,
    onExternalLink: ((URL) -> Void)? = nil
  ) {
    self.init(
      url: url,
      title: title,
      externalLinkBehavior: externalLinkBehavior,
      onNavigation: onNavigation,
      onExternalLink: onExternalLink
    )
  }

  public init(
    url string: String,
    title: String? = nil,
    externalLinkBehavior: WebExternalLinkBehavior = .allowInWebContent,
    onNavigation: ((WebNavigation) -> Void)? = nil,
    onExternalLink: ((URL) -> Void)? = nil
  ) {
    self.init(
      url: _webContentURL(string),
      title: title,
      externalLinkBehavior: externalLinkBehavior,
      onNavigation: onNavigation,
      onExternalLink: onExternalLink
    )
  }

  public init(
    html: String,
    baseURL: URL? = nil,
    title: String? = nil,
    externalLinkBehavior: WebExternalLinkBehavior = .allowInWebContent,
    onNavigation: ((WebNavigation) -> Void)? = nil,
    onExternalLink: ((URL) -> Void)? = nil
  ) {
    self.init(
      .html(html, baseURL: baseURL),
      configuration: WebContentConfiguration(title: title ?? "Web content", externalLinkBehavior: externalLinkBehavior),
      onNavigation: onNavigation,
      onExternalLink: onExternalLink
    )
  }

  /// The model's observable state, useful for status UI outside this view.
  public var navigationState: WebNavigationState { model.navigationState }
  public var content: WebContent { model.content }
  public var url: URL? { model.url }
  public var title: String { configuration.title }

  public func reload() { model.reload() }
  public func goBack() { model.goBack() }
  public func goForward() { model.goForward() }

  /// Adds a callback without exposing the underlying iframe event model.
  public func onNavigation(perform action: @escaping (WebNavigation) -> Void) -> WebContentView {
    var copy = self
    copy.onNavigation = action
    return copy
  }

  /// Adds an external-link callback. The configured
  /// ``WebExternalLinkBehavior`` still determines whether the link is allowed,
  /// opened externally, or cancelled.
  public func onExternalLink(perform action: @escaping (URL) -> Void) -> WebContentView {
    var copy = self
    copy.onExternalLink = action
    return copy
  }

  public func onError(perform action: @escaping (WebContentError) -> Void) -> WebContentView {
    var copy = self
    copy.onError = action
    return copy
  }

  public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("iframe")
    node.classes = ["web-view", "web-content"]
    node.attributes["title"] = configuration.title
    node.attributes["loading"] = "lazy"
    node.attributes["referrerpolicy"] = "no-referrer"
    node.attributes["data-web-content"] = "true"
    node.attributes["data-web-external-links"] = configuration.externalLinkBehavior.rawValue
    if let command = model._consumeCommand() {
      node.attributes["data-web-command"] = command
    }

    switch model.content {
    case .url(let url):
      // A `javascript:` address in an iframe would run in this page's origin; it loads nothing instead.
      if !_isScriptURL(url.absoluteString) { node.attributes["src"] = url.absoluteString }
      node.attributes["data-web-source"] = "url"
    case .html(let html, let baseURL):
      node.attributes["srcdoc"] = _webHTMLWithBaseURL(html, baseURL: baseURL)
      // Inline HTML gets an opaque origin: its scripts run, but never with
      // the application's cookies, storage, or DOM. Popups it opens stay
      // sandboxed too (no `allow-popups-to-escape-sandbox`), so they keep
      // the sandbox's navigation limits instead of escaping them.
      node.attributes["sandbox"] = "allow-scripts allow-forms allow-popups"
      node.attributes["data-web-source"] = "html"
      if let baseURL { node.attributes["data-web-base-url"] = baseURL.absoluteString }
    }

    let requestedURL = model.content.url
    let kind = model._navigationKind()
    node.events["load"] = _EventHandler(name: "load", action: {
      model._didFinishLoading(url: requestedURL)
      onNavigation?(WebNavigation(url: requestedURL, kind: kind))
    })
    node.events["error"] = _EventHandler(name: "error", action: {
      let error = WebContentError(message: "The browser could not load this web content.", url: requestedURL)
      model._didFailLoading(message: error.message, url: requestedURL)
      onError?(error)
    })
    node.events["web-navigation"] = _EventHandler(name: "web-navigation", action: { value in
      guard let url = _webContentURLIfValid(value) else { return }
      model._didNavigate(to: url, sameOrigin: true)
      onNavigation?(WebNavigation(url: url, kind: .link, isSameOrigin: true))
    })
    if onExternalLink != nil {
      node.events["web-external-link"] = _EventHandler(name: "web-external-link", action: { value in
        guard let url = _webContentURLIfValid(value) else { return }
        onExternalLink?(url)
      })
    }
    return node
  }
}


/// Resolves the `String` convenience initializers to a URL.
///
/// Web addresses always go through `URL(string:)`, matching how SwiftUI and
/// WebKit callers build request URLs. Only a scheme-less string is treated
/// as a file-system path: turning a malformed `http://` string into a file
/// URL is a category error (and a Foundation API-misuse trap). A malformed
/// URL that carries a scheme resolves to `about:blank`, which is what WebKit
/// displays when a navigation cannot be started.
private func _webContentURL(_ string: String) -> URL {
  if let url = URL(string: string) { return url }
  if _webContentHasURLScheme(string) { return URL(string: "about:blank")! }
  return URL(fileURLWithPath: string)
}

/// RFC 3986 scheme: `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":"`.
private func _webContentHasURLScheme(_ string: String) -> Bool {
  var isFirst = true
  for byte in string.utf8 {
    let isAlpha = (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
    if byte == 58 { return !isFirst }
    if isFirst {
      guard isAlpha else { return false }
      isFirst = false
      continue
    }
    let isDigit = byte >= 48 && byte <= 57
    guard isAlpha || isDigit || byte == 43 || byte == 45 || byte == 46 else { return false }
  }
  return false
}

private func _webContentURLIfValid(_ string: String) -> URL? {
  return URL(string: string)
}

func _webHTMLWithBaseURL(_ html: String, baseURL: URL?) -> String {
  guard let baseURL else { return html }
  let base = "<base href=\"" + _webEscapeHTMLAttribute(baseURL.absoluteString) + "\">"
  // A <base> before the doctype puts the document in quirks mode, so it goes just after the doctype (past any leading
  // white space and comments). There the parser opens the head for it, whatever follows; no later markup is searched,
  // since a "<head" can sit inside a comment or an attribute. Without a doctype it leads the fragment as before.
  let bytes = Array(html.utf8)
  var insertAt = 0
  var index = 0
  while index < bytes.count {
    if bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A || bytes[index] == 0x0D || bytes[index] == 0x0C {
      index += 1
    } else if _webHasPrefixIgnoringASCIICase(bytes, at: index, "<!--"), let end = _webFind(Array("-->".utf8), in: bytes, from: index + 4) {
      index = end + 3
    } else {
      break
    }
  }
  if _webHasPrefixIgnoringASCIICase(bytes, at: index, "<!doctype"), let close = bytes[index...].firstIndex(of: UInt8(ascii: ">")) {
    insertAt = close + 1
  }
  let prefix = String(decoding: bytes[..<insertAt], as: UTF8.self)
  let rest = String(decoding: bytes[insertAt...], as: UTF8.self)
  return prefix + base + rest
}

private func _webHasPrefixIgnoringASCIICase(_ bytes: [UInt8], at start: Int, _ prefix: String) -> Bool {
  let expected = Array(prefix.utf8)
  guard start + expected.count <= bytes.count else { return false }
  for offset in 0..<expected.count {
    var byte = bytes[start + offset]
    if byte >= 0x41 && byte <= 0x5A { byte += 0x20 }
    if byte != expected[offset] { return false }
  }
  return true
}

/// The index of the first `needle` in `bytes` at or after `start`.
private func _webFind(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
  guard !needle.isEmpty, bytes.count >= needle.count else { return nil }
  var index = start
  while index + needle.count <= bytes.count {
    if bytes[index] == needle[0], Array(bytes[index ..< index + needle.count]) == needle { return index }
    index += 1
  }
  return nil
}

private func _webEscapeHTMLAttribute(_ value: String) -> String {
  var result = ""
  result.reserveCapacity(value.utf8.count)
  for character in value {
    switch character {
    case "&": result.append("&amp;")
    case "\"": result.append("&quot;")
    case "<": result.append("&lt;")
    case ">": result.append("&gt;")
    default: result.append(character)
    }
  }
  return result
}
