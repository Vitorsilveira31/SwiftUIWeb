import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite
@MainActor
final class AccessibilityBackendTests {
  private func node<V: View>(_ view: V) -> _RenderNode {
    FiberTree(view).renderNode
  }

  private func find(_ node: _RenderNode, control: String) -> _RenderNode? {
    if node.attributes["data-control-kind"] == control { return node }
    for child in node.children {
      if let match = find(child, control: control) { return match }
    }
    return nil
  }

  private func descendant(_ node: _RenderNode, attribute: String, value: String) -> _RenderNode? {
    if node.attributes[attribute] == value { return node }
    for child in node.children {
      if let match = descendant(child, attribute: attribute, value: value) { return match }
    }
    return nil
  }

  @Test
  func testModifierBackendResolvesNativeRolesAndStates() {
    let native = node(
      Button("Save", action: {})
        .accessibilityLabel("Commit")
        .accessibilityAddTraits([.isButton, .updatesFrequently])
    )
    _expectEqual(native.attributes["aria-label"], "Commit")
    _expectNil(native.attributes["role"], "native button must not receive redundant role=button")
    _expectEqual(native.attributes["aria-live"], "polite")
    _expectEqual(native.attributes["data-a11y-backend"], "1")

    let custom = node(
      Text("Action").accessibilityAddTraits(.isButton).accessibilityValue("Ready")
    )
    _expectEqual(custom.attributes["role"], "button")
    _expectEqual(custom.attributes["aria-description"], "Ready")
    _expectNil(custom.attributes["aria-valuetext"])
  }

  @Test
  func testValueAndHintFollowWrappedControlsWithRoleAppropriateARIA() throws {
    let root = node(Button("Genre", action: {}).padding(10).fixedSize()
      .accessibilityValue("Selected").accessibilityHint("Filter stories"))
    let button = try #require(find(root, control: "button"))
    #expect(button.attributes["aria-description"] == "Selected. Filter stories")
    #expect(button.attributes["aria-valuetext"] == nil)
    #expect(root.attributes["aria-valuetext"] == nil)
    let reversed = node(Button("Genre", action: {}).accessibilityHint("Filter stories")
      .accessibilityValue("Selected"))
    #expect(reversed.attributes["aria-description"] == "Selected. Filter stories")
    let range = node(HTMLElement(tag: "input", attributes: ["type": "range"]) {}
      .accessibilityValue("Half full").accessibilityHint("Adjust volume"))
    #expect(range.attributes["aria-valuetext"] == "Half full")
    #expect(range.attributes["aria-description"] == "Adjust volume")
  }

  @Test
  func testHiddenFalseRemovesStaleAccessibilityState() {
    let hidden = node(Text("Secret").accessibilityHidden(true))
    _expectEqual(hidden.attributes["aria-hidden"], "true")
    let visible = node(Text("Secret").accessibilityHidden(false))
    _expectNil(visible.attributes["aria-hidden"])
    _expectEqual(visible.attributes["data-a11y-backend"], "1")
  }

  @Test
  func testHiddenAndNonHitTestableSubtreeIsInertRegardlessOfModifierOrder() {
    let hiddenAfterHitTesting = Button("Open menu", action: {})
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    let hiddenBeforeHitTesting = Button("Open menu", action: {})
      .accessibilityHidden(true)
      .allowsHitTesting(false)
    let rendered = node(hiddenAfterHitTesting)
    let reordered = node(hiddenBeforeHitTesting)

    _expectEqual(rendered.attributes["aria-hidden"], "true")
    _expectEqual(rendered.attributes["data-allows-hit-testing"], "false")
    _expectEqual(rendered.attributes["inert"], "")
    _expectEqual(reordered.attributes["inert"], "")
    _expectTrue(StaticHTMLFiberRenderer().render(hiddenAfterHitTesting).contains("inert=\"\""))

    let restored = node(Button("Open menu", action: {}).allowsHitTesting(false).accessibilityHidden(false))
    _expectNil(restored.attributes["aria-hidden"])
    _expectNil(restored.attributes["inert"])
  }

  @Test
  func testDisabledTraitAddsAriaOnlyWhenNativeMarkupCannotExpressIt() {
    let custom = node(Text("Unavailable").accessibilityAddTraits(.isDisabled))
    _expectEqual(custom.attributes["aria-disabled"], "true")

    let native = node(
      HTMLElement(tag: "button", attributes: ["disabled": "disabled"]) {}
        .accessibilityAddTraits(.isDisabled)
    )
    _expectEqual(native.attributes["disabled"], "disabled")
    _expectNil(native.attributes["aria-disabled"])
  }

  @Test
  func testControlsExposeNativeAndARIAStateThroughOneBackend() {
    var enabled = false
    let toggle = Toggle("Enabled", isOn: Binding(get: { enabled }, set: { enabled = $0 }))
    let toggleNode = find(node(toggle), control: "toggle")
    _expectEqual(descendant(toggleNode!, attribute: "role", value: "switch")?.attributes["aria-checked"], "false")

    let slider = Slider(value: .constant(0.5), in: 0...1)
    let sliderNode = find(node(slider), control: "slider")
    _expectEqual(sliderNode?.attributes["aria-valuemin"], "0")
    _expectEqual(sliderNode?.attributes["aria-valuemax"], "1")
    _expectEqual(descendant(sliderNode!, attribute: "type", value: "range")?.attributes["aria-valuenow"], "0.5")
  }

  @Test
  func testPresentationSurfaceIsModalAndNamed() {
    let alert = node(
      Text("Root").alert("Delete", isPresented: .constant(true), actions: { Button("Cancel", action: {}) })
    )
    let alertDialog = descendant(alert, attribute: "role", value: "alertdialog")
    _expectEqual(alertDialog?.attributes["aria-label"], "Delete")
    _expectEqual(alertDialog?.attributes["data-presentation"], "alert")
    let alertHTML = StaticHTMLFiberRenderer().render(
      Text("Root").alert("Delete", isPresented: .constant(true), actions: { Button("Cancel", action: {}) })
    )
    _expectTrue(alertHTML.contains("<h2"), alertHTML)

    let sheet = node(
      Text("Root").sheet(isPresented: .constant(true)) {
        VStack { Text("Menu contents") }.accessibilityLabel("Navigation menu")
      }
    )
    let sheetDialog = descendant(sheet, attribute: "role", value: "dialog")
    _expectEqual(sheetDialog?.attributes["aria-label"], "Navigation menu")
  }
}
