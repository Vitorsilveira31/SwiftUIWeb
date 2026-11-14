import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
import SwiftUIWebHTML

/// Pure layout containers are hit-transparent on the web, as in SwiftUI: a
/// tap on a dialog's empty spacer area reaches the dimmed backdrop beneath
/// it. Anything that paints, listens or scrolls keeps its pointer events.
@Suite
@MainActor
struct HitTestingTests {
  private func html<V: View>(_ view: V) -> String { StaticHTMLFiberRenderer().render(view) }
  private func node<V: View>(_ view: V) -> _RenderNode { FiberTree(view).renderNode }

  private func nodes(_ root: _RenderNode, where predicate: (_RenderNode) -> Bool) -> [_RenderNode] {
    var found: [_RenderNode] = []
    func walk(_ node: _RenderNode) {
      if predicate(node) { found.append(node) }
      for child in node.children { walk(child) }
    }
    walk(root)
    return found
  }

  @Test
  func emptyLayoutContainersPassPointerEventsThrough() {
    let overlay = node(
      ZStack {
        Color.black.opacity(0.4).onTapGesture {}
        VStack(spacing: 0) {
          Spacer(minLength: 20)
          Text("Dialog").padding(24).background(Color.white)
          Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    )
    let scrims = nodes(overlay) { $0.events["click"] != nil }
    let scrimsBlock = scrims.allSatisfy { !$0._isHitTransparent }
    #expect(scrims.count == 1)
    #expect(scrimsBlock, "the tappable backdrop keeps its events")
    let layouts = nodes(overlay) { ["zstack", "vstack", "spacer", "frame"].contains($0.attributes["data-layout-kind"] ?? "") }
    let layoutsPass = layouts.allSatisfy { $0._isHitTransparent }
    #expect(layouts.count >= 4)
    #expect(layoutsPass, "stacks, spacers and frames paint nothing")
    let painted = nodes(overlay) { node in node.styles.keys.contains { $0.hasPrefix("background") } }
    let paintedBlock = painted.allSatisfy { !$0._isHitTransparent }
    #expect(!painted.isEmpty)
    #expect(paintedBlock, "a painted layer blocks hits")
    let markup = html(
      ZStack {
        Color.black.opacity(0.4).onTapGesture {}
        VStack { Spacer(); Text("Dialog").background(Color.white); Spacer() }
      }
    )
    #expect(markup.contains("vstack passthrough"))
    #expect(markup.contains("flex-spacer passthrough"))
  }

  @Test
  func paintedListeningAndScrollingContainersKeepTheirPointerEvents() {
    #expect(!node(VStack { Text("a") }.background(Color.red))._isHitTransparent)
    #expect(!node(VStack { Text("a") }.onTapGesture {})._isHitTransparent)
    #expect(!node(VStack { Text("a") }.contentShape(Rectangle()))._isHitTransparent)
    #expect(!node(VStack { Text("a") }.onHover { _ in })._isHitTransparent)
    #expect(!node(VStack { Text("a") }.focusable())._isHitTransparent)
    #expect(!node(ScrollView { Text("a") })._isHitTransparent)
    #expect(!node(Text("a"))._isHitTransparent, "only layout wrappers are candidates")
    #expect(node(VStack { Text("a") }.onAppear {})._isHitTransparent, "lifecycle callbacks are not gestures")
    #expect(!html(ScrollView { Text("a") }).contains("passthrough"))
  }
}
