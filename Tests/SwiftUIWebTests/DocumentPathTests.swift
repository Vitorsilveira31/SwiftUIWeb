import Testing
import SwiftUIWeb
import SwiftUIWebWeb
import SwiftUIWebFiber
import SwiftUIWebHTML

@Suite
@MainActor
final class DocumentPathTests {
  /// The attribute the browser host reads, as the page renders it.
  private func path<V: View>(_ view: V) -> String? {
    let page = FiberTree(view).renderNode.htmlDescription
    guard let start = page.range(of: "data-url-path=\"") else { return nil }
    let rest = page[start.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return nil }
    return String(rest[..<end])
  }

  @Test
  func testTheSegmentsAreJoinedWithSlashes() {
    #expect(path(Text("x").path("en", "components", "slider")) == "en/components/slider")
    #expect(path(Text("x").path(["pt", "story"])) == "pt/story")
  }

  @Test
  func testEmptySegmentsAndSlashesAreDropped() {
    #expect(_documentPath(["", "a", "/", "b/c"]) == "a/bc")
    #expect(_documentPath([]) == "")
  }

  @Test
  func testASegmentIsPercentEscaped() {
    #expect(_documentPath(["Stack View", "é", "a.b-c_d~e"]) == "Stack%20View/%C3%A9/a.b-c_d~e")
  }

  @Test
  func testATextRootGetsAWrapperThatTakesNoPartInLayout() {
    let page = FiberTree(Text("Home").path("home")).renderNode.htmlDescription
    #expect(page.contains("data-url-path=\"home\""))
    #expect(page.contains("display: contents") || page.contains("display:contents"))
    #expect(page.contains("Home"))
  }

  @Test
  func testAnElementRootCarriesTheAttributeItself() {
    let page = FiberTree(VStack { Text("a") }.path("a")).renderNode.htmlDescription
    #expect(page.contains("data-url-path=\"a\""))
    #expect(!page.contains("display: contents"))
  }
}
