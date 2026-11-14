import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebHTML

/// The byte serializer must stay byte-for-byte compatible with the historical
/// five-entity escaping and deterministic attribute order.
@Suite
@MainActor
struct StaticHTMLSerializerTests {
  @Test
  func escapesTheFiveEntitiesInTextAndAttributesAndKeepsUnicode() {
    let node = _RenderNode.element("div")
    node.attributes["title"] = "a&b<c>\"d'e ção"
    node.attributes["data-z"] = "1"
    node.attributes["data-a"] = "2"
    node.classes = ["k1", "k2"]
    node.styles = ["color": "red", "background": "blue"]
    let text = _RenderNode.text("x & y < z > \"q\" 'r' ✓")
    node.children = [text]

    let html = StaticHTMLFiberRenderer().renderNode(node)
    #expect(html == "<div class=\"k1 k2\" data-a=\"2\" data-z=\"1\" style=\"background: blue; color: red;\" title=\"a&amp;b&lt;c&gt;&quot;d&#39;e ção\">x &amp; y &lt; z &gt; &quot;q&quot; &#39;r&#39; ✓</div>")
  }

  @Test
  func markupInTextIsEscapedVoidTagsHaveNoCloseAndBytesMatchTheString() {
    let container = _RenderNode.element("p")
    let raw = _RenderNode.text("<b>bold</b>")
    let image = _RenderNode.element("img")
    image.attributes["alt"] = "x"
    container.children = [raw, image, _RenderNode.empty()]

    let renderer = StaticHTMLFiberRenderer()
    #expect(renderer.renderNode(container) == "<p>&lt;b&gt;bold&lt;/b&gt;<img alt=\"x\"></p>")
    #expect(String(decoding: renderer.renderNodeUTF8(container), as: UTF8.self) == renderer.renderNode(container))
  }

  @Test
  func styledTextBecomesASpanAndFragmentsFlatten() {
    let text = _RenderNode.text("hi")
    text.classes = ["t"]
    let fragment = _RenderNode.fragment()
    fragment.children = [text, _RenderNode.text("plain")]
    #expect(StaticHTMLFiberRenderer().renderNode(fragment) == "<span class=\"t\">hi</span>plain")
  }

  @Test
  func rendererEscapesTextContent() {
    let html = StaticHTMLFiberRenderer().render(Text("<script>alert('x')</script>"))
    _expectFalse(html.contains("<script>"))
    _expectTrue(html.contains("&lt;script&gt;"))
  }
}
