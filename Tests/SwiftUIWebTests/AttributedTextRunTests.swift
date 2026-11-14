import Testing
import SwiftUIWeb

@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures

@_spi(Renderer) @testable import SwiftUIWebFeatures

@MainActor
@Suite("AttributedText runs")
struct AttributedTextRunTests {
  @Test func unstyledSingleRunIsPlainText() {
    let text = Text(_attributedRuns: [_AttributedRun(text: "Plain", attributes: _TextAttributes())])
    let node = text._render(in: _RenderContext())
    #expect(node.kind == .text)
    #expect(node.text == "Plain")
  }

  @Test func kernAndLinkRunsRenderAsInlineSpans() {
    var kerned = _TextAttributes()
    kerned.kern = 2
    var linked = _TextAttributes()
    linked.linkString = "https://example.test"
    linked.underlineStyle = .single
    linked.strikethroughStyle = Text.LineStyle(pattern: .dash)
    let text = Text(_attributedRuns: [
      _AttributedRun(text: "A", attributes: _TextAttributes()),
      _AttributedRun(text: "B", attributes: kerned),
      _AttributedRun(text: "C", attributes: linked),
    ])
    let node = text._render(in: _RenderContext())
    #expect(node.attributes["aria-label"] == "ABC")
    #expect(node.children.count == 3)
    #expect(node.children[0].text == "A")
    #expect(node.children[1].styles["letter-spacing"] == "2px")
    let anchor = node.children[2]
    #expect(anchor.attributes["href"] == "https://example.test")
    #expect(anchor.children[0].styles["text-decoration-line"] == "underline line-through")
    #expect(anchor.children[0].attributes["data-text-href"] == nil)
    // A link takes the tint, and its tap is handled by the environment's openURL, not the browser's navigation.
    #expect(anchor.styles["color"] == Color.accentColor.cssValue)
    #expect(anchor.events["click"]?.preventsDefault == true)
  }

  @Test func aLinkTapCallsTheEnvironmentOpenURLAction() {
    var opened: [String] = []
    var context = _RenderContext()
    context.environment.openURL = OpenURLAction { url in
      opened.append(url.absoluteString)
      return .handled
    }
    var linked = _TextAttributes()
    linked.linkString = "#contents"
    let node = Text(_attributedRuns: [
      _AttributedRun(text: "See ", attributes: _TextAttributes()),
      _AttributedRun(text: "contents", attributes: linked),
    ])._render(in: context)
    node.children[1].events["click"]?.action()
    #expect(opened == ["#contents"])
  }

  @Test func aScriptLinkStaysPlainText() {
    var unsafe = _TextAttributes()
    unsafe.linkString = "javascript:alert(document.domain)"
    var safe = _TextAttributes()
    safe.linkString = "/docs?page=2"
    let text = Text(_attributedRuns: [
      _AttributedRun(text: "A", attributes: unsafe),
      _AttributedRun(text: "B", attributes: safe),
    ])
    let node = text._render(in: _RenderContext())
    #expect(node.children.count == 2)
    #expect(node.children[0].kind != .element("a"))
    #expect(node.children[0].attributes["href"] == nil)
    #expect(node.children[0].attributes["data-text-href"] == nil)
    #expect(node.children[1].attributes["href"] == "/docs?page=2")
  }

  @Test func commonAttributesDropDifferences() {
    var first = _TextAttributes()
    first.kern = 1
    first.baselineOffset = 3
    var second = _TextAttributes()
    second.kern = 1
    let common = first._common(with: second)
    #expect(common.kern == 1)
    #expect(common.baselineOffset == nil)
  }
}
