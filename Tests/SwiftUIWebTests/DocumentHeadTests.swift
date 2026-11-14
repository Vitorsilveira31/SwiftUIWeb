import Testing
import SwiftUIWeb
import SwiftUIWebWeb
import SwiftUIWebFiber
import SwiftUIWebHTML

@Suite
@MainActor
final class DocumentHeadTests {
  /// The attribute the browser host reads, as the JSON it carries (the renderer escapes quotes for the HTML).
  private func headJSON<V: View>(_ view: V) -> String? {
    let page = FiberTree(view).renderNode.htmlDescription
    guard let start = page.range(of: "data-document-head=\"") else { return nil }
    let rest = page[start.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return nil }
    return String(rest[..<end]).replacingOccurrences(of: "&quot;", with: "\"")
  }

  @Test
  func testEveryElementKindRendersAsJSON() {
    let json = headJSON(
      Text("Orders").documentHead {
        HeadElement.favicon("/alert.png", type: "image/png", sizes: "32x32", media: "(prefers-color-scheme: dark)")
        HeadElement.meta(name: "robots", content: "noindex")
        HeadElement.meta(property: "og:title", content: "Orders")
        HeadElement.themeColor("#121118", media: "(prefers-color-scheme: dark)")
        HeadElement.canonical("https://example.test/orders")
      })
    #expect(json == """
      [{"tag":"link","attrs":{"rel":"icon","href":"/alert.png","type":"image/png","sizes":"32x32","media":"(prefers-color-scheme: dark)"}},\
      {"tag":"meta","attrs":{"name":"robots","content":"noindex"}},\
      {"tag":"meta","attrs":{"property":"og:title","content":"Orders"}},\
      {"tag":"meta","attrs":{"name":"theme-color","content":"#121118","media":"(prefers-color-scheme: dark)"}},\
      {"tag":"link","attrs":{"rel":"canonical","href":"https://example.test/orders"}}]
      """)
  }

  @Test
  func testOptionalAttributesAreLeftOutWhenNil() {
    let json = headJSON(Text("x").documentHead { HeadElement.favicon("/a.ico"); HeadElement.themeColor("#fff") })
    #expect(json == ##"[{"tag":"link","attrs":{"rel":"icon","href":"/a.ico"}},{"tag":"meta","attrs":{"name":"theme-color","content":"#fff"}}]"##)
  }

  @Test
  func testTheBuilderSupportsConditionsAndLoops() {
    func json(_ alert: Bool, _ names: [String]) -> String? {
      headJSON(
        Text("x").documentHead {
          if alert { HeadElement.favicon("/alert.png") } else { HeadElement.favicon("/ok.png") }
          if names.isEmpty { HeadElement.meta(name: "robots", content: "noindex") }
          for name in names { HeadElement.meta(name: name, content: "1") }
          [HeadElement.canonical("/c")]
        })
    }
    #expect(json(true, []) == #"[{"tag":"link","attrs":{"rel":"icon","href":"/alert.png"}},{"tag":"meta","attrs":{"name":"robots","content":"noindex"}},{"tag":"link","attrs":{"rel":"canonical","href":"/c"}}]"#)
    #expect(json(false, ["a", "b"]) == #"[{"tag":"link","attrs":{"rel":"icon","href":"/ok.png"}},{"tag":"meta","attrs":{"name":"a","content":"1"}},{"tag":"meta","attrs":{"name":"b","content":"1"}},{"tag":"link","attrs":{"rel":"canonical","href":"/c"}}]"#)
  }

  @Test
  func testQuotesBackslashesControlCharactersAndUnicodeAreEscaped() {
    let json = headJSON(Text("x").documentHead { HeadElement.meta(name: "description", content: "a \"b\" \\ c\nd\te\u{1}f ação 日本") })
    #expect(json == #"[{"tag":"meta","attrs":{"name":"description","content":"a \"b\" \\ c\u000ad\u0009e\u0001f ação 日本"}}]"#)
  }

  @Test
  func testAnEmptyBlockStillMarksTheNode() {
    #expect(headJSON(Text("x").documentHead {}) == "[]")
  }

  @Test
  func testAnElementRootKeepsItsOwnNodeAndATextRootGetsATransparentWrapper() {
    let stack = FiberTree(VStack { Text("a"); Text("b") }.documentHead { HeadElement.canonical("/c") }).renderNode.htmlDescription
    #expect(stack.contains("data-document-head="))
    #expect(!stack.contains("display: contents"))
    let text = FiberTree(Text("a").documentHead { HeadElement.canonical("/c") }).renderNode.htmlDescription
    #expect(text.contains("display: contents"))
    #expect(text.contains(">a</div>"))
  }
}
