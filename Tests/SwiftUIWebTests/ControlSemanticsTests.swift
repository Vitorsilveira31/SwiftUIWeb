import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
final class ControlSemanticsTests {
  private func find(_ node: _RenderNode, tag: String? = nil, control: String? = nil) -> _RenderNode? {
    if case let .element(name) = node.kind,
       (tag == nil || name == tag),
       (control == nil || node.attributes["data-control-kind"] == control) { return node }
    for child in node.children {
      if let result = find(child, tag: tag, control: control) { return result }
    }
    return nil
  }

  @Test
  func testControlsExposeSemanticMetadataAndAccessibilityValues() {
    var enabled = false
    var slider = 0.5
    let view = VStack {
      Button("Save", role: .destructive, action: {}).controlSize(.large).tint(.red)
      Toggle("Enabled", isOn: Binding(get: { enabled }, set: { enabled = $0 }))
      Slider(value: Binding(get: { slider }, set: { slider = $0 }), in: 0...1)
      ProgressView(value: 2, total: 4)
      Gauge(value: 3, in: 0...4) { Text("Capacity") }
      Menu("More") { Button("Reset", action: {}) }
      ShareLink(item: "swift")
    }
    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("data-control-kind=\"button\""))
    _expectTrue(html.contains("data-control-size=\"large\""))
    _expectTrue(html.contains("data-role=\"destructive\""))
    _expectTrue(html.contains("data-control-kind=\"toggle\""))
    _expectTrue(html.contains("aria-valuenow=\"0.5\""))
    _expectTrue(html.contains("aria-valuenow=\"2\""))
    _expectTrue(html.contains("data-control-kind=\"gauge\""))
    _expectTrue(html.contains("aria-haspopup=\"menu\""))
    _expectTrue(html.contains("data-control-kind=\"share-link\""))
  }

  @Test
  func testToggleUsesBrowserCheckedValueInsteadOfBlindToggle() {
    var value = false
    let tree = FiberTree(Toggle("Enabled", isOn: Binding(get: { value }, set: { value = $0 })))
    tree.dispatch(event: "change", value: "true")
    _expectTrue(value)
    // A repeated browser event carrying the same checked state is idempotent.
    tree.dispatch(event: "change", value: "true")
    _expectTrue(value)
    tree.dispatch(event: "change", value: "false")
    _expectFalse(value)
  }

  @Test
  func testSliderClampsOutOfRangeBrowserValues() {
    var value = 0.5
    let tree = FiberTree(Slider(value: Binding(get: { value }, set: { value = $0 }), in: 0...1))
    tree.dispatch(event: "input", value: "9")
    _expectEqual(value, 1)
    tree.dispatch(event: "input", value: "-3")
    _expectEqual(value, 0)
    tree.dispatch(event: "input", value: "not-a-number")
    _expectEqual(value, 0)
  }

  @Test
  func testSliderWithoutExplicitStepRemainsContinuous() {
    let html = StaticHTMLFiberRenderer().render(Slider(value: .constant(0.5), in: 0...1))
    _expectTrue(html.contains("data-control-kind=\"slider\""))
    _expectTrue(html.contains("step=\"any\""))
  }

  @Test
  func testControlIdentityAndCustomShareStyleSurviveRenders() {
    let share = ShareLink(item: "swift", label: { Text("Share it") }).buttonStyle(.bordered).controlSize(.small)
    let renderer = StaticHTMLFiberRenderer()
    let first = renderer.render(share)
    let second = renderer.render(share)
    _expectEqual(first, second)
    _expectTrue(first.contains("data-button-style=\"bordered\""))
    _expectTrue(first.contains("data-control-size=\"small\""))
    _expectTrue(first.contains("Share it"))
  }
}
