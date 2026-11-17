import Foundation
import Testing
import SwiftUIWeb
import SwiftUIWebWeb
import SwiftUIWebFiber
import SwiftUIWebHTML

@Suite
@MainActor
final class WebContentTests {
  @Test
  func testPublicValueTypesExposeConsistentDefaultsAndAliases() {
    let url = URL(string: "https://app.example.test/settings")!
    let html = WebContent.html("<p>Local document</p>")
    let basedHTML = WebContent.html("<p>Based document</p>", baseURL: url)

    _expectNil(html.url)
    _expectEqual(basedHTML.url, url)
    _expectEqual(WebContent.url(url).url, url)
    _expectEqual(WebExternalLinkBehavior.allow, .allowInWebContent)
    _expectEqual(WebExternalLinkBehavior.deny, .cancel)

    let error = WebContentError(message: "Blocked", code: 7, url: url)
    _expectEqual(error.description, "Blocked")
    _expectEqual(error.code, 7)
    _expectEqual(error.url, url)

    var state = WebNavigationState(
      url: url,
      title: "Settings",
      loadState: .loading,
      canGoBack: true,
      canGoForward: false,
      error: error
    )
    _expectTrue(state.isLoading)
    _expectEqual(state.title, "Settings")
    _expectTrue(state.canGoBack)
    _expectFalse(state.canGoForward)
    state.loadState = .loaded
    _expectFalse(state.isLoading)

    let initialNavigation = WebNavigation(url: nil, kind: .initial)
    _expectTrue(initialNavigation.isMainFrame)
    _expectFalse(initialNavigation.isSameOrigin)
    let subframeNavigation = WebNavigation(
      url: url,
      kind: .link,
      isMainFrame: false,
      isSameOrigin: true
    )
    _expectFalse(subframeNavigation.isMainFrame)
    _expectTrue(subframeNavigation.isSameOrigin)
  }

  @Test
  func testLoadingURLAndHTMLSourcesReportsTheCorrectNavigationKind() {
    let start = URL(string: "https://app.example.test/start")!
    let destination = URL(string: "https://app.example.test/next")!
    let base = URL(string: "https://app.example.test/base?first=1&second=2")!
    let model = WebContentModel(url: start)
    var navigations: [WebNavigation] = []

    model.load(destination.absoluteString)
    _expectEqual(model.content, .url(destination))
    _expectEqual(model.url, destination)
    _expectTrue(model.isLoading)

    let urlView = WebContentView(model: model).onNavigation { navigations.append($0) }
    let urlTree = FiberTree(urlView)
    let urlHTML = StaticHTMLFiberRenderer().render(urlView)
    _expectTrue(urlHTML.contains("src=\"https://app.example.test/next\""), urlHTML)
    _expectTrue(urlHTML.contains("loading=\"lazy\""), urlHTML)
    urlTree.dispatch(event: "load")
    _expectEqual(model.navigationState.loadState, .loaded)
    _expectEqual(navigations.last?.kind, .urlRequest)
    _expectEqual(navigations.last?.url, destination)

    model.loadHTMLString("<h1>Local document</h1>", baseURL: base)
    _expectEqual(model.content, .html("<h1>Local document</h1>", baseURL: base))
    _expectEqual(model.url, base)

    let htmlView = WebContentView(model: model, configuration: WebContentConfiguration(title: "Preview"))
      .onNavigation { navigations.append($0) }
    let htmlTree = FiberTree(htmlView)
    let html = StaticHTMLFiberRenderer().render(htmlView)
    _expectTrue(html.contains("title=\"Preview\""), html)
    _expectTrue(html.contains("srcdoc="), html)
    _expectTrue(html.contains("first=1"), html)
    _expectTrue(html.contains("second=2"), html)
    htmlTree.dispatch(event: "load")
    _expectEqual(model.navigationState.loadState, .loaded)
    _expectEqual(navigations.last?.kind, .html)
    _expectEqual(navigations.last?.url, base)

    model.load(destination)
    _expectEqual(model.content, .url(destination))
    _expectTrue(model.isLoading)
  }

  @Test
  func testHistoryStateErrorsAndCommandSequenceFollowLifecycle() {
    let url = URL(string: "https://app.example.test/page")!
    let model = WebContentModel(url: url)
    model.updateHistoryAvailability(canGoBack: true, canGoForward: true)
    _expectTrue(model.canGoBack)
    _expectTrue(model.canGoForward)

    var reportedError: WebContentError?
    let view = WebContentView(model: model).onError { reportedError = $0 }
    let errorTree = FiberTree(view)
    errorTree.dispatch(event: "error")
    _expectEqual(model.navigationState.loadState, .failed)
    _expectEqual(model.error?.message, "The browser could not load this web content.")
    _expectEqual(model.error?.url, url)
    _expectEqual(reportedError, model.error)

    model.reload()
    _expectNil(model.error)
    _expectTrue(model.isLoading)
    _expectEqual(StaticHTMLFiberRenderer().render(WebContentView(model: model)).contains(
      "data-web-command=\"1:reload\""
    ), true)

    model.goBack()
    _expectEqual(StaticHTMLFiberRenderer().render(WebContentView(model: model)).contains(
      "data-web-command=\"2:back\""
    ), true)
    model.goForward()
    _expectEqual(StaticHTMLFiberRenderer().render(WebContentView(model: model)).contains(
      "data-web-command=\"3:forward\""
    ), true)

    model.loadHTML("<p>new document</p>")
    _expectNil(model.url)
    _expectFalse(model.canGoBack)
    _expectFalse(model.canGoForward)
  }

  @Test
  func testInitializerSpellingsAndViewModifiersKeepTheirConfiguration() {
    let url = URL(string: "https://app.example.test/document")!
    let sourceView = WebContentView(source: .url(url))
    _expectEqual(sourceView.content, .url(url))
    _expectEqual(WebContentView(url: url, title: "URL title", externalLinkBehavior: .cancel).title, "URL title")
    _expectEqual(WebContentView(url: url.absoluteString, title: "String URL").content, .url(url))
    _expectEqual(WebContentModel(url: "https://app.example.test/document").url, url)
    _expectEqual(WebContentView(url).url, url)

    // A malformed web address must never be reinterpreted as a file path.
    let malformedWebURL = WebContentModel(url: "http://[invalid").url
    _expectTrue(malformedWebURL?.isFileURL == false)
    _expectEqual(malformedWebURL?.absoluteString, "about:blank")
    _expectEqual(WebContentView(url: "https://[bad", title: "Bad").content.url?.absoluteString, "about:blank")
    // An empty address has no scheme to protect, so it keeps the native
    // file-path interpretation instead of becoming about:blank.
    let emptyAddress = WebContentModel(url: "").url
    _expectTrue(emptyAddress?.isFileURL == true)
    // Digits, "+", "-" and "." are legal after a scheme's first letter, so a
    // malformed custom-scheme address is still recognized as a web address.
    _expectEqual(WebContentModel(url: "a1+-.://[bad").url?.absoluteString, "about:blank")

    let htmlView = WebContentView(html: "<p>Inline</p>", title: "Inline title")
    _expectEqual(htmlView.content, .html("<p>Inline</p>", baseURL: nil))
    _expectEqual(htmlView.title, "Inline title")
    let html = StaticHTMLFiberRenderer().render(htmlView)
    _expectTrue(html.contains("srcdoc=\"&lt;p&gt;Inline&lt;/p&gt;\""), html)
    // Popups stay inside the sandbox: no escape token, so a popup the frame
    // opens keeps the frame's restrictions instead of escaping them.
    _expectTrue(html.contains("sandbox=\"allow-scripts allow-forms allow-popups\""), html)
    _expectFalse(html.contains("allow-popups-to-escape-sandbox"), html)
    _expectFalse(html.contains("allow-top-navigation"), html)
    _expectFalse(html.contains("allow-same-origin"), html)
    _expectTrue(html.contains("referrerpolicy=\"no-referrer\""), html)
    _expectEqual(WebContentView(html: "<p>Default title</p>").title, "Web content")
    _expectEqual(WebContentModel(html: "<p>Model</p>").content, .html("<p>Model</p>", baseURL: nil))

    let configured = StaticHTMLFiberRenderer().render(
      WebContentView(url: url, externalLinkBehavior: .openExternally)
    )
    _expectTrue(configured.contains("data-web-external-links=\"openExternally\""), configured)
  }

  @Test
  func testNavigationAndExternalLinkCallbacksIgnoreMalformedURLs() {
    let start = URL(string: "https://app.example.test/start")!
    let next = URL(string: "https://app.example.test/next")!
    let outside = URL(string: "https://outside.example.test/page")!
    let model = WebContentModel(url: start)
    var navigations: [WebNavigation] = []
    var externalLinks: [URL] = []
    let view = WebContentView(model: model)
      .onNavigation { navigations.append($0) }
      .onExternalLink { externalLinks.append($0) }
    let tree = FiberTree(view)

    tree.dispatch(event: "web-navigation", value: "http://[invalid")
    _expectEqual(model.url, start)
    _expectTrue(navigations.isEmpty)
    tree.dispatch(event: "web-external-link", value: "http://[invalid")
    _expectTrue(externalLinks.isEmpty)

    tree.dispatch(event: "web-navigation", value: next.absoluteString)
    _expectEqual(model.url, next)
    _expectEqual(navigations.last?.kind, .link)
    _expectTrue(navigations.last?.isSameOrigin == true)
    tree.dispatch(event: "web-external-link", value: outside.absoluteString)
    _expectEqual(externalLinks, [outside])
  }

  @Test
  func testHTMLWithoutBaseURLDoesNotInventNavigationURLOnSuccessOrFailure() {
    let successfulModel = WebContentModel(html: "<p>Local success</p>")
    let successTree = FiberTree(WebContentView(model: successfulModel))
    successTree.dispatch(event: "load")
    _expectNil(successfulModel.url)
    _expectEqual(successfulModel.navigationState.loadState, .loaded)

    let failedModel = WebContentModel(html: "<p>Local failure</p>")
    var reportedError: WebContentError?
    let failedTree = FiberTree(WebContentView(model: failedModel).onError { reportedError = $0 })
    failedTree.dispatch(event: "error")
    _expectNil(failedModel.url)
    _expectNil(failedModel.error?.url)
    _expectNil(reportedError?.url)
    _expectEqual(failedModel.navigationState.loadState, .failed)
  }

  @Test
  func testAScriptAddressNeverReachesTheIframeSource() {
    for address in ["javascript:alert(document.domain)", "JavaScript:alert(1)", "vbscript:x"] {
      let html = StaticHTMLFiberRenderer().render(WebContentView(model: WebContentModel(url: URL(string: address)!)))
      _expectFalse(html.contains("src="), html)
      _expectTrue(html.contains("data-web-source=\"url\""), html)
    }
    let data = StaticHTMLFiberRenderer().render(WebContentView(model: WebContentModel(url: URL(string: "data:text/html,%3Cp%3Ehi")!)))
    _expectTrue(data.contains("src=\"data:text/html,%3Cp%3Ehi\""), data)
  }

  @Test
  func testLoadReplacesPendingCommandsAndRenderKeepsCommandUntilAcknowledged() {
    let model = WebContentModel(url: URL(string: "https://app.example.test/page")!)
    model.reload()
    let firstRender = StaticHTMLFiberRenderer().render(WebContentView(model: model))
    let secondRender = StaticHTMLFiberRenderer().render(WebContentView(model: model))
    _expectTrue(firstRender.contains("data-web-command=\"1:reload\""), firstRender)
    _expectTrue(secondRender.contains("data-web-command=\"1:reload\""), secondRender)

    model.goBack()
    model.loadHTML("<h1>Replacement</h1>")
    let replacement = StaticHTMLFiberRenderer().render(WebContentView(model: model))
    _expectFalse(replacement.contains("data-web-command="), replacement)
    _expectTrue(replacement.contains("data-web-source=\"html\""), replacement)
  }

  @Test
  func testViewNavigationMethodsForwardToTheInjectedModel() {
    let model = WebContentModel(url: URL(string: "https://app.example.test/page")!)
    let view = WebContentView(model: model)

    view.reload()
    _expectTrue(view.navigationState.isLoading)
    _expectTrue(StaticHTMLFiberRenderer().render(view).contains(
      "data-web-command=\"1:reload\""
    ))

    view.goBack()
    _expectTrue(StaticHTMLFiberRenderer().render(view).contains(
      "data-web-command=\"2:back\""
    ))
    view.goForward()
    _expectTrue(StaticHTMLFiberRenderer().render(view).contains(
      "data-web-command=\"3:forward\""
    ))
  }

  @Test
  func testSameOriginHTMLRendersAsIframeAndDeliversNavigationEvents() {
    let model = WebContentModel(
      .html("<a href=\"/next\">Next</a>", baseURL: URL(string: "https://app.example.test/start")!)
    )
    var navigated: WebNavigation?
    var external: URL?
    let view = WebContentView(
      model: model,
      configuration: WebContentConfiguration(externalLinkBehavior: .cancel),
      onNavigation: { navigated = $0 },
      onExternalLink: { external = $0 }
    )

    let tree = FiberTree(view)
    let html = StaticHTMLFiberRenderer().renderNode(tree.renderNode)

    _expectTrue(html.contains("<iframe"), html)
    _expectTrue(html.contains("srcdoc="), html)
    _expectTrue(html.contains("&lt;base href=&quot;https://app.example.test/start&quot;&gt;"), html)
    _expectTrue(html.contains("data-web-content=\"true\""), html)
    _expectTrue(html.contains("data-web-external-links=\"cancel\""), html)
    _expectTrue(html.contains("data-web-base-url=\"https://app.example.test/start\""), html)

    tree.dispatch(event: "web-navigation", value: "https://app.example.test/next")
    _expectEqual(model.navigationState.url?.absoluteString, "https://app.example.test/next")
    _expectEqual(model.navigationState.loadState, .loaded)
    _expectEqual(navigated?.kind, .link)
    _expectEqual(navigated?.isSameOrigin, true)

    tree.dispatch(event: "web-external-link", value: "https://outside.example.test")
    _expectEqual(external?.absoluteString, "https://outside.example.test")
  }

  @Test
  func testCrossOriginURLDoesNotClaimInspectableNavigationOrDOMAccess() {
    let model = WebContentModel(url: URL(string: "https://outside.example.test/page")!)
    let view = WebContentView(
      model: model,
      configuration: WebContentConfiguration(externalLinkBehavior: .openExternally)
    )
    let html = StaticHTMLFiberRenderer().render(view)

    _expectTrue(html.contains("src=\"https://outside.example.test/page\""), html)
    _expectTrue(html.contains("data-web-content=\"true\""), html)
    // The public render contract contains only URL/source metadata. There is
    // no DOM handle, script bridge, or fabricated same-origin capability.
    _expectFalse(html.contains("contentDocument"), html)
    _expectFalse(html.contains("javascript:"), html)
    _expectFalse(model.navigationState.canGoBack)
    _expectFalse(model.navigationState.canGoForward)
  }

  @Test
  func testNavigationCommandsAreObservableAndReloadPreservesSource() {
    let model = WebContentModel(url: URL(string: "https://app.example.test")!)
    _expectEqual(model.navigationState.loadState, .idle)

    model.reload()
    _expectTrue(model.navigationState.isLoading)
    let reloadHTML = StaticHTMLFiberRenderer().render(WebContentView(model: model))
    _expectTrue(reloadHTML.contains("data-web-command=\"1:reload\""), reloadHTML)

    model.goBack()
    let backHTML = StaticHTMLFiberRenderer().render(WebContentView(model: model))
    _expectTrue(backHTML.contains("data-web-command=\"2:back\""), backHTML)
    _expectEqual(model.content.url?.absoluteString, "https://app.example.test")
  }

  @Test
  func testObservableLoadingAndErrorState() {
    let model = WebContentModel(url: URL(string: "https://app.example.test/fails")!)
    let tree = FiberTree(WebContentView(model: model).onError { _ in })

    tree.dispatch(event: "load")
    _expectEqual(model.navigationState.loadState, .loaded)
    tree.dispatch(event: "error")
    _expectEqual(model.navigationState.loadState, .failed)
    _expectNotNil(model.navigationState.error)
  }

  @Test
  func inlineDocumentBaseGoesAfterLeadingWhitespaceAndDoctype() {
    let base = URL(string: "https://app.example.test/start")!
    let model = WebContentModel(.html("  \n<!doctype html><p>Doc</p>", baseURL: base))
    let html = StaticHTMLFiberRenderer().renderNode(FiberTree(WebContentView(model: model)).renderNode)
    _expectTrue(
      html.contains("&lt;!doctype html&gt;&lt;base href=&quot;https://app.example.test/start&quot;&gt;"),
      html
    )
  }

  @Test
  func inlineDocumentBaseOpensBeforeACommentThatNeverCloses() {
    let base = URL(string: "https://app.example.test/start")!
    let model = WebContentModel(.html("<!-- never closed <p>Doc</p>", baseURL: base))
    let html = StaticHTMLFiberRenderer().renderNode(FiberTree(WebContentView(model: model)).renderNode)
    _expectTrue(
      html.contains("&lt;base href=&quot;https://app.example.test/start&quot;&gt;&lt;!-- never closed"),
      html
    )
  }
}
