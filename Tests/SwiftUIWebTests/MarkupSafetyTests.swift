import Testing
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
import SwiftUIWeb

/// Caller-supplied URLs and markup names must not turn into script: a link
/// keeps only safe schemes, and `HTMLElement` refuses executable tags and
/// event-handler attributes.
@MainActor
struct MarkupSafetyTests {
  @Test func urlAttributesKeepOnlySafeSchemes() {
    for safe in ["https://example.com", "http://a.b/c", "mailto:a@b.c", "tel:+5511", "/relative", "page?x=1", "#top", "", "a/b:c"] {
      #expect(_safeURLAttribute(safe) == safe)
    }
    for unsafe in ["javascript:alert(1)", "JavaScript:alert(1)", " javascript:alert(1)", "java\tscript:alert(1)", "\u{1}javascript:x", "data:text/html,<b>", "vbscript:x"] {
      #expect(_safeURLAttribute(unsafe) == nil)
    }
  }

  @Test func onlyScriptSchemesAreScriptURLs() {
    for script in ["javascript:alert(1)", "JavaScript:alert(1)", " javascript:alert(1)", "java\tscript:alert(1)", "\u{1}vbscript:x"] {
      #expect(_isScriptURL(script))
    }
    for other in ["https://example.com", "data:text/html,<b>", "blob:https://a.b/c", "about:blank", "/relative", "page?x=javascript:1", "#javascript:x", "", "a/b:c"] {
      #expect(!_isScriptURL(other))
    }
  }

  @Test func elementAndAttributeNamesRejectInjection() {
    #expect(_isSafeElementName("section"))
    #expect(_isSafeElementName("my-widget"))
    for name in ["script", "SCRIPT", "iframe", "img onerror=x", "", "1a", "a>b", "set", "animate", "animateTransform", "link", "base"] {
      #expect(!_isSafeElementName(name))
    }
    #expect(_isSafeAttributeName("aria-label"))
    #expect(_isSafeAttributeName("data-id"))
    for name in ["onclick", "ONload", "a b", "x=\"y\"", "", "-x", "a>"] {
      #expect(!_isSafeAttributeName(name))
    }
  }

  @Test func linkDropsUnsafeHref() {
    let safe = StaticHTMLFiberRenderer().render(Link("Docs", destination: URL(string: "https://example.com/docs")!))
    #expect(safe.contains("href=\"https://example.com/docs\""))
    let unsafe = StaticHTMLFiberRenderer().render(Link("Bad", destination: URL(string: "javascript:alert(1)")!))
    #expect(!unsafe.contains("href="))
    #expect(!unsafe.contains("javascript:"))
  }

  @Test func htmlElementSanitizesTagAndAttributes() {
    let html = StaticHTMLFiberRenderer().render(
      HTMLElement(tag: "script", attributes: ["onclick": "x()", "href": "javascript:x()", "data-id": "7", "title": "ok"])
    )
    #expect(html.contains("<div"))
    #expect(!html.contains("<script"))
    #expect(!html.contains("onclick"))
    #expect(!html.contains("javascript:"))
    #expect(html.contains("data-id=\"7\""))
    #expect(html.contains("title=\"ok\""))
  }

  @Test func canvasSymbolMarkupPassesTheSameFilters() {
    let canvas = Canvas(renderer: { context, _ in
      if let symbol = context.resolveSymbol(id: 1) { context.draw(symbol, at: .zero) }
    }, symbols: {
      HTMLElement(tag: "script", attributes: ["onclick": "x()", "href": "javascript:x()", "data-id": "7"]).tag(1)
    })
    let node = FiberTree(canvas).renderNode
    guard case .symbol(let markup, _, _, _, _, _) = node._canvasCommands.first else {
      Issue.record("expected the symbol")
      return
    }
    #expect(!markup.contains("<script"))
    #expect(!markup.contains("onclick"))
    #expect(!markup.contains("javascript:"))
    #expect(markup.contains("data-id=\"7\""))
    #expect(_safeAttributeValue(name: "onload", value: "x") == nil)
    #expect(_safeAttributeValue(name: "src", value: "javascript:x") == nil)
    #expect(_safeAttributeValue(name: "title", value: "javascript:x") == "javascript:x")
  }

  @Test func hoverRuleCannotCloseItsDeclarationOrStyleElement() {
    let css = _hoverRuleCSS(
      ownerSelector: "#a", triggerSelector: "#a",
      targets: [(selector: "#a", isOwnerRoot: true, declarations: ["color": "red}body{display:none", "x}y": "1", "opacity": "1;</style><script>"], hasTransition: true, animation: nil)]
    )
    #expect(css == "#a:hover{color:redbodydisplay:none !important;opacity:1/stylescript !important}")
  }
}
