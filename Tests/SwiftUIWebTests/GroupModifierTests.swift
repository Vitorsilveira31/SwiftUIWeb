import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A modifier on a `Group` applies to each child, as in SwiftUI. A Group
/// renders as a fragment with no DOM host, so gestures, hit regions and
/// attributes written onto the fragment itself would never reach the page
/// (the scrim of a dialog stopped closing on tap for exactly that reason).
@Suite
@MainActor
struct GroupModifierTests {
  private func elements(_ node: _RenderNode) -> [_RenderNode] {
    var found: [_RenderNode] = []
    func walk(_ node: _RenderNode) {
      if node.kind != .fragment { found.append(node) }
      for child in node.children { walk(child) }
    }
    walk(node)
    return found
  }

  @Test
  func gesturesHitRegionsAndAttributesReachEveryChildOfAGroup() {
    var taps = 0
    var hovers: [Bool] = []
    let tree = FiberTree(
      Group {
        Color.black
        Text("second")
      }
      .ignoresSafeArea()
      .contentShape(Rectangle())
      .accessibilityLabel("Backdrop")
      .onHover { hovers.append($0) }
      .onTapGesture { taps += 1 }
    )
    let hosts = elements(tree.renderNode).filter { $0.events["click"] != nil }
    #expect(hosts.count == 2, "both children carry the tap")
    #expect(hosts.allSatisfy { $0.attributes["data-content-shape"] == "rectangle" })
    #expect(hosts.allSatisfy { $0.attributes["data-ignores-safe-area"] == "true" })
    #expect(hosts.allSatisfy { $0.attributes["aria-label"] == "Backdrop" })
    #expect(hosts.allSatisfy { $0.events["mouseenter"] != nil && $0.events["mouseleave"] != nil })
    tree.dispatch(event: "click", on: hosts[0])
    tree.dispatch(event: "click", on: hosts[1])
    tree.dispatch(event: "mouseenter", on: hosts[1])
    #expect(taps == 2)
    #expect(hovers == [true])
    let html = StaticHTMLFiberRenderer().render(Group { Color.black; Text("second") }.onTapGesture {})
    #expect(html.components(separatedBy: "data-fiber-event-click").count == 3, "both children are serialized with the tap")
  }
}
