import Foundation
import Testing
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures

/// Source-side contracts. Browser measurement and layout geometry have separate
/// integration suites; these verify Swift emits intent without losing events.
@Suite
@MainActor
final class SemanticLayoutIntegrationTests {
  private func collect(_ node: _RenderNode) -> [_RenderNode] {
    [node] + node.children.flatMap(collect)
  }

  @Test
  func testFrameAndPaddingRemainSeparateModifierBoundaries() {
    // Both stay boundaries of their own in the layout (the layout sees a frame around a padding); they share an element
    // (`_SemanticLayers`): the frame is the element, the padding its layer.
    let node = Text("Title").padding(12).frame(maxWidth: .infinity, alignment: .leading)
      ._render(in: _RenderContext())
    _expectEqual(node.attributes["data-layout-kind"], "frame")
    _expectEqual(node.attributes["data-frame-max-w"], "inf")
    _expectEqual(node.attributes["data-align-x"], "0")
    let layers = _SemanticLayers.layers(of: node)
    _expectEqual(layers.map(\.kind), ["frame", "padding"])
    _expectEqual(layers.last?.value("padding-leading"), "12.0")
    _expectFalse(node.children.isEmpty)
  }

  @Test
  func testWrappersDoNotDuplicateButtonEvents() {
    var count = 0
    let node = Button("Refresh") { count += 1 }.padding(8).frame(width: 120, height: 40)
      ._render(in: _RenderContext())
    let interactive = collect(node).filter { $0.events["click"] != nil }
    _expectEqual(interactive.count, 1)
    _expectTrue(node.events.isEmpty)
    interactive.first?.events["click"]?.action()
    _expectEqual(count, 1)
  }

  @Test
  func testSafeAreaInsetPreservesOneRefreshAction() {
    let node = Button("Refresh") {}.safeAreaInset(edge: .bottom) { Text("Inset") }
      ._render(in: _RenderContext())
    _expectEqual(node.attributes["data-layout-kind"], "inset")
    _expectEqual(node.attributes["data-inset-edge"], "bottom")
    _expectEqual(collect(node).filter { $0.events["click"] != nil }.count, 1)
  }

  @Test
  func testFixedSizePreservesChosenAxes() {
    let node = Text("Text").fixedSize(horizontal: false, vertical: true)._render(in: _RenderContext())
    _expectEqual(node.attributes["data-layout-kind"], "fixed")
    _expectEqual(node.attributes["data-fixed-x"], "false")
    _expectEqual(node.attributes["data-fixed-y"], "true")
  }

  @Test
  func testBuiltInAnyLayoutRetainsSemanticIntent() {
    let layout = AnyLayout(HStackLayout(alignment: .top, spacing: 13))
    _expectEqual(layout._swiftUIWebSemanticLayout?["data-layout-kind"], "hstack")
    _expectEqual(layout._swiftUIWebSemanticLayout?["data-layout-gap"], "13.0")
  }

  @Test
  func testPresentationNeverNestsDialogInsideButton() {
    var presented = true
    let binding = Binding(get: { presented }, set: { presented = $0 })
    let node = Button("Open") {}.sheet(isPresented: binding) { Text("Sheet") }
      ._render(in: _RenderContext())
    _expectEqual(node.attributes["data-presentation-host"], "true")
    let button = collect(node).first { if case .element("button") = $0.kind { return true }; return false }
    _expectNotNil(button)
    _expectFalse(collect(button!).contains { $0.classes.contains("presentation-root") })
    let presentation = collect(node).first { $0.classes.contains("presentation-root") }
    presentation?.events["presentation-dismiss"]?.action()
    _expectFalse(presented)
  }

  @Test
  func testDismissedPresentationStillHasStableModifierBoundary() {
    let node = Button("Open") {}.sheet(isPresented: .constant(false)) { Text("Sheet") }
      ._render(in: _RenderContext())
    _expectEqual(node.attributes["data-presentation-host"], "true")
    _expectEqual(collect(node).filter { $0.events["click"] != nil }.count, 1)
    _expectFalse(collect(node).contains { $0.classes.contains("presentation-root") })
  }

  @Test
  func testNegativeLayoutPriorityIsNotDiscarded() {
    let node = Text("Lower").layoutPriority(-2)._render(in: _RenderContext())
    _expectEqual(node.attributes["data-layout-priority"].flatMap(Double.init), -2)
  }
}
