import Foundation
import Testing
import SwiftUIWebCore
import SwiftUIWebFeatures
import SwiftUIWebFiber
import SwiftUIWebHTML

/// These tests intentionally import the implementation layers directly. They
/// ensure the façade is a compatibility convenience rather than a hidden
/// dependency cycle between Core, Fiber, and HTML.
@Suite(.processGlobalState)
@MainActor
final class ModuleBoundaryTests {
  @Test
  func testCoreFiberAndHTMLComposeWithoutFacade() {
    let view = VStack {
      Text("Layered")
      Button("Action") {}
    }

    let tree = FiberTree(view)
    let html = StaticHTMLFiberRenderer().renderNode(tree.renderNode)

    _expectTrue(html.contains("Layered"))
    _expectTrue(html.contains("Action"))
    _expectEqual(tree.root.renderNode.kind, .element("div"))
  }

  @Test
  func testDirectHTMLSerializationIsDeterministic() {
    let view = Text("same")
    let direct = StaticHTMLFiberRenderer().render(view)

    // The façade is tested through the existing @testable import in
    // FiberRenderingTests; this assertion documents the intended boundary:
    // direct HTML serialization is deterministic and backend-neutral.
    _expectEqual(direct, "same")
  }

  @Test
  func testHTMLRendererConvenienceEntrypointsAndRootTag() {
    let renderer = StaticHTMLFiberRenderer(rootTag: "main")
    _expectEqual(renderer.rootTag, "main")

    struct DemoApp: App {
      var body: some View { WindowGroup { Text("app tree") } }
    }

    let tree = renderer.renderTree(Text("tree"))
    _expectEqual(tree.renderNode.htmlDescription, "tree")
    _expectEqual(renderer.renderHTML(Text("html")), "html")
    _expectTrue(renderer.renderTree(DemoApp()).root.renderNode.htmlDescription.contains("app tree"))

    let previousTitle = AppTitleRuntime.current
    defer { AppTitleRuntime.current = previousTitle }
    DemoApp._setTitle("Boundary")
    _expectEqual(AppTitleRuntime.current, "Boundary")
    DemoApp._launch(DemoApp(), with: DemoApp._configuration)
    DemoApp.main()
  }

  @Test
  func testHTMLRendererCoversFragmentsMarkupTextVoidElementsAndEventFiltering() {
    let renderer = StaticHTMLFiberRenderer()

    let empty = _RenderNode.empty()
    _expectEqual(renderer.renderNode(empty), "")

    let text = _RenderNode.text("<&>")
    text.attributes = ["title": "a\"b"]
    text.classes = ["z", "a"]
    text.styles = ["z-index": "2", "color": "red"]
    text.events = [
      "click": _EventHandler(name: "click", action: {}),
      "task": _EventHandler(name: "task", action: {}),
      "appear": _EventHandler(name: "appear", action: {}),
    ]
    let raw = _RenderNode.text("<b>raw</b>")
    let fragment = _RenderNode.fragment()
    fragment.children = [text, raw]
    let fragmentHTML = renderer.renderNode(fragment)
    _expectTrue(fragmentHTML.contains("&lt;&amp;&gt;"))
    _expectTrue(fragmentHTML.contains("&lt;b&gt;raw&lt;/b&gt;"))
    _expectFalse(fragmentHTML.contains("<b>"))
    _expectTrue(fragmentHTML.contains("data-fiber-event-click=\"click\""))
    _expectFalse(fragmentHTML.contains("data-fiber-event-task"))
    _expectFalse(fragmentHTML.contains("data-fiber-event-appear"))

    let image = _RenderNode.element("IMG")
    image.attributes = ["alt": "cover"]
    _expectEqual(renderer.renderNode(image), "<IMG alt=\"cover\">")

    let section = _RenderNode.element("section")
    section.children = [_RenderNode.text("body")]
    _expectEqual(renderer.renderNode(section), "<section>body</section>")
  }
}
