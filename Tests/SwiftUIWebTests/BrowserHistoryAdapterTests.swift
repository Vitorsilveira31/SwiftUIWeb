import Foundation
import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebBrowser

/// The native build of the browser history adapter: URL mapping, tab URLs and
/// the observer/scope surface Fiber talks to. The History API itself only
/// exists in the Embedded browser build.
@Suite
@MainActor
final class BrowserHistoryAdapterTests {
  private static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~%/")

  @Test
  func rootPathMapsToTheDocumentRoot() {
    let adapter = BrowserHistoryAdapter()
    #expect(adapter.path(for: NavigationPath()) == "/")
  }

  @Test
  func typedPathsBecomePercentEncodedURLSegments() {
    let adapter = BrowserHistoryAdapter()
    for value in ["detail", "hello world", "quote\"s?#&", "naïve", "tab\u{1}control"] {
      var navigationPath = NavigationPath()
      navigationPath.append(value)
      navigationPath.append(42)
      let url = adapter.path(for: navigationPath)
      #expect(url.hasPrefix("/"))
      // Every byte outside RFC 3986's unreserved set is escaped, so a typed
      // value can never inject a query, fragment or extra path separator.
      #expect(url.allSatisfy { Self.unreserved.contains($0) }, "\(url)")
      let decoded = url.split(separator: "/").map { String($0).removingPercentEncoding }
      let raw = navigationPath._historyPathDescription().split(separator: "/").map(String.init)
      #expect(decoded == raw.map { Optional($0) })
    }
  }

  @Test
  func reservedAndSingleByteCharactersAreEscapedWithTwoHexDigits() {
    let adapter = BrowserHistoryAdapter()
    var navigationPath = NavigationPath()
    navigationPath.append("hello world")
    navigationPath.append("a\u{1}b?")
    #expect(adapter.path(for: navigationPath) == "/hello%20world/a%01b%3F")
  }

  @Test
  func tabSelectionsMapToAQueryItemAndRestoreTheirHistoryEntry() {
    let adapter = BrowserHistoryAdapter()
    var observed: [String] = []
    adapter._observeTab(namespace: "root-tabs") { observed.append($0) }
    adapter._setTabDefault(namespace: "root-tabs", tag: "home")
    adapter._updateTab(namespace: "root-tabs", tag: "settings")
    // Selecting a tab records history; it does not echo back to the observer.
    #expect(observed.isEmpty)

    let token = _tabHistoryNamespaceToken("root-tabs")
    let tagToken = _tabHistoryNamespaceToken("root-tabs|settings")
    var tabPath = NavigationPath()
    tabPath.append("__tab:\(token)")
    tabPath.append(tagToken)
    #expect(adapter.path(for: tabPath) == "/?tab-selection=\(token)%3A\(tagToken)")
    // Namespaces hash to stable, URL-safe tokens.
    #expect(token == _tabHistoryNamespaceToken("root-tabs"))
    #expect(token.allSatisfy { $0.isHexDigit })
    #expect(token != tagToken)
  }

  /// The page reports the location after every tab URL Swift pushed. A report that names the tab already shown selects
  /// nothing, so the Embedded host skips the root pass it would otherwise force.
  @Test
  func aLocationNamingTheShownTabSelectsNothing() {
    let adapter = BrowserHistoryAdapter()
    adapter._updateTab(namespace: "root-tabs", tag: "settings")
    let token = _tabHistoryNamespaceToken("root-tabs")
    let settings = _tabHistoryNamespaceToken("root-tabs|settings")
    let home = _tabHistoryNamespaceToken("root-tabs|home")
    #expect(!adapter._locationShowsTab(namespaceToken: token, tagToken: settings), "the URL Swift just pushed")
    #expect(adapter._locationShowsTab(namespaceToken: token, tagToken: home), "another tab, from the address bar")
    #expect(!adapter._locationShowsTab(namespaceToken: token, tagToken: home), "reported again")
    #expect(adapter._locationShowsTab(namespaceToken: _tabHistoryNamespaceToken("nested-tabs"), tagToken: home), "a namespace never shown")
  }

  @Test
  func nativeAdapterSharesOneScopeAndIgnoresHistoryOperations() {
    let adapter = BrowserHistoryAdapter()
    #expect(adapter._scope("nested-stack") as? BrowserHistoryAdapter === adapter)
    var restored: [NavigationPath] = []
    adapter.observe { restored.append($0) }
    var navigationPath = NavigationPath()
    navigationPath.append("detail")
    adapter.update(navigationPath)
    adapter.apply(.push(path: adapter.path(for: navigationPath)))
    adapter.apply(.replace(path: "/"))
    adapter.apply(.back(path: "/"))
    // Without a browser there is no popstate, so nothing is restored.
    #expect(restored.isEmpty)
    var popstates = 0
    adapter.onPopstate = { popstates += 1 }
    adapter.onPopstate?()
    #expect(popstates == 1)
  }
}
