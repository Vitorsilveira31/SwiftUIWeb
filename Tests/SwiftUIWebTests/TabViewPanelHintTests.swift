import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber

/// A tab built for the first time starts its geometry readers at the size of the box the panels share, as the host
/// last measured it (`_TabMountTracker.panelSize`), not at the size of an enclosing reader: beside a sidebar that one
/// is the window, and a layout that depends on the width (a grid's column count) was laid out wide and corrected a
/// round trip later.
@Suite
@MainActor
struct TabViewPanelHintTests {
  private enum Pane: Hashable { case home, works }

  /// The widths a reader rendered at, in order.
  private final class Widths { var values: [Int] = [] }

  private struct Host: View {
    @State var selection = Pane.home
    let widths: Widths
    var body: some View {
      GeometryReader { _ in
        TabView(selection: $selection) {
          Tab("Home", systemImage: "house", value: Pane.home) { Text("home") }
          Tab("Works", systemImage: "book", value: Pane.works) {
            GeometryReader { proxy in
              let _ = widths.values.append(Int(proxy.size.width))
              Text("works \(Int(proxy.size.width))")
            }
          }
        }
        .tabViewStyle(.sidebarAdaptable)
      }
    }
  }

  @Test
  func aTabBuiltLaterStartsItsReadersAtThePanelsSize() throws {
    let widths = Widths()
    let tree = FiberTree(Host(widths: widths))
    let window = try #require(tree.findNode(withEvent: "geometry"))
    tree.dispatch(event: "geometry", value: "0,0,1280,800", on: window)
    let panels = try #require(tree.findNode(withEvent: "geometryChange"))
    #expect(panels.attributes["data-tab-content"] == "true")
    tree.dispatch(event: "geometryChange", value: "248,0,1032,800", on: panels)
    #expect(widths.values.isEmpty, "the works tab is built when it is first selected")

    let works = try #require(findTab("Works", in: tree.renderNode))
    tree.dispatch(event: "click", on: works)
    _ = tree.renderNode
    #expect(widths.values.first == 1032, "the works reader rendered at \(widths.values)")
    #expect(tree.renderNode.htmlDescription.contains("works 1032"))
  }

  @Test
  func withoutAMeasurementOfThePanelsATabStartsAtTheEnclosingReadersSize() throws {
    let widths = Widths()
    let tree = FiberTree(Host(widths: widths))
    let window = try #require(tree.findNode(withEvent: "geometry"))
    tree.dispatch(event: "geometry", value: "0,0,1280,800", on: window)
    let works = try #require(findTab("Works", in: tree.renderNode))
    tree.dispatch(event: "click", on: works)
    _ = tree.renderNode
    #expect(widths.values.first == 1280, "the works reader rendered at \(widths.values)")
  }
}

private func findTab(_ label: String, in node: _RenderNode) -> _RenderNode? {
  if node.attributes["role"] == "tab", node.attributes["data-tab-label"] == label { return node }
  for child in node.children {
    if let found = findTab(label, in: child) { return found }
  }
  return nil
}
