import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

private final class PressLog { var values: [Bool] = []; var enabled: [Bool] = []; var triggers = 0 }

private struct RecordingPressStyle: ButtonStyle {
  let log: PressLog
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    log.values.append(configuration.isPressed)
    log.enabled.append(isEnabled)
    return configuration.label.opacity(configuration.isPressed ? 0.5 : 1)
  }
}

private struct DoubleTapStyle: PrimitiveButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button(configuration)
  }
}

@Suite
@MainActor
struct ControlStyleParityTests {
  private func all(_ node: _RenderNode, _ predicate: (_RenderNode) -> Bool) -> [_RenderNode] {
    (predicate(node) ? [node] : []) + node.children.flatMap { all($0, predicate) }
  }
  private func text(_ node: _RenderNode) -> String {
    (node.text ?? "") + node.children.map(text).joined()
  }

  @Test
  func segmentedPickerRendersARadioGroupAndSelectsSegments() {
    struct Fixture: View {
      @State var selection = "day"
      var value: String { selection }
      var body: some View {
        Picker("Range", selection: $selection) {
          Text("Day").tag("day")
          Text("Week").tag("week")
          Text("Month").tag("month")
        }
        .pickerStyle(.segmented)
      }
    }
    let fixture = Fixture()
    let tree = FiberTree(fixture)
    let group = all(tree.renderNode) { $0.attributes["role"] == "radiogroup" }.first
    #expect(group?.attributes["data-picker-style"] == "segmented")
    #expect(group?.attributes["aria-label"] == "Range")
    #expect(all(tree.renderNode) { $0.kind == .element("select") }.isEmpty)
    let segments = all(tree.renderNode) { $0.attributes["role"] == "radio" }
    #expect(segments.map { text($0) } == ["Day", "Week", "Month"])
    #expect(segments.map { $0.attributes["aria-checked"] } == ["true", "false", "false"])
    #expect(segments.map { $0.attributes["tabindex"] } == ["0", "-1", "-1"])
    tree.dispatch(event: "click", on: segments[2])
    #expect(fixture.value == "month")
    _ = tree.update(fixture)
    let updated = all(tree.renderNode) { $0.attributes["role"] == "radio" }
    #expect(updated.map { $0.attributes["aria-checked"] } == ["false", "false", "true"])
  }

  @Test
  func toggleStylesRenderSwitchCheckboxAndButton() {
    let tree = FiberTree(VStack {
      Toggle("Switch", isOn: .constant(true))
      Toggle("Check", isOn: .constant(false)).toggleStyle(.checkbox)
      Toggle("Bold", isOn: .constant(true)).toggleStyle(.button)
    })
    let toggles = all(tree.renderNode) { $0.attributes["data-control-kind"] == "toggle" }
    #expect(toggles.map { $0.attributes["data-toggle-style"] } == ["switch", "checkbox", "button"])
    let inputs = all(tree.renderNode) { $0.attributes["type"] == "checkbox" }
    #expect(inputs[0].attributes["role"] == "switch")
    #expect(inputs[1].attributes["role"] == nil)
    #expect(toggles[2].kind == .element("button"))
    #expect(toggles[2].attributes["aria-pressed"] == "true")
  }

  @Test
  func buttonToggleFlipsTheBinding() {
    struct Fixture: View {
      @State var on = false
      var value: Bool { on }
      var body: some View { Toggle("Bold", isOn: $on).toggleStyle(.button) }
    }
    let fixture = Fixture()
    let tree = FiberTree(fixture)
    tree.dispatch(event: "click")
    #expect(fixture.value)
  }

  @Test
  func labelsHiddenRemovesVisibleLabelsButKeepsAccessibleNames() {
    let tree = FiberTree(VStack {
      Toggle("Notifications", isOn: .constant(true))
      Stepper("Quantity", value: .constant(1), in: 0...5)
      ColorPicker("Accent", selection: .constant(Color.blue))
      Picker("Language", selection: .constant("Swift")) { Text("Swift").tag("Swift") }
    }.labelsHidden())
    let html = tree.renderNode.htmlDescription
    #expect(!html.contains(">Notifications<"))
    #expect(!html.contains(">Quantity<"))
    #expect(!html.contains(">Accent<"))
    #expect(!html.contains(">Language<"))
    #expect(html.contains("aria-label=\"Notifications\""))
    #expect(html.contains("aria-label=\"Quantity\""))
    #expect(html.contains("aria-label=\"Accent\""))
    #expect(html.contains("aria-label=\"Language\""))
    let visible = FiberTree(Toggle("Notifications", isOn: .constant(true))).renderNode.htmlDescription
    #expect(visible.contains(">Notifications<"))
  }

  @Test
  func sliderLabelNamesTheControlWithoutDrawingIt() {
    let html = FiberTree(Slider(value: .constant(0.5), in: 0...1) { Text("Volume") }).renderNode.htmlDescription
    #expect(html.contains("aria-label=\"Volume\""))
    #expect(!html.contains(">Volume<"))
  }

  @Test
  func detentsSizeTheSheetAndStartAtTheSmallestDetent() {
    struct Fixture: View {
      @State var presented = true
      var body: some View {
        Text("Root").sheet(isPresented: $presented) {
          Text("Sheet").presentationDetents([.large, .height(240), .medium])
        }
      }
    }
    let tree = FiberTree(Fixture())
    let sheet = all(tree.renderNode) { $0.classes.contains("sheet-panel") }.first
    #expect(sheet?.styles["--presentation-detent-height"] == "240.0px")
    #expect(sheet?.attributes["data-presentation-detent-selection"] == "height(240.0)")
    #expect(sheet?.attributes["data-presentation-resizable"] == "true")
    #expect(sheet?.attributes["data-presentation-detent-heights"] == "height(240.0)=240.0px;medium=50dvh;large=calc(100dvh - 24px)")
    // Without a selection binding the choice is kept in Fiber state. The
    // sheet content re-renders with the new detent (the browser host mirrors
    // it onto the sheet surface after the commit).
    tree.dispatch(event: "presentation-detent", value: "large", on: sheet)
    let content = all(tree.renderNode) { $0.attributes["data-presentation-detent-height"] != nil }.first
    #expect(content?.attributes["data-presentation-detent-selection"] == "large")
    #expect(content?.attributes["data-presentation-detent-height"] == "calc(100dvh - 24px)")
  }

  @Test
  func fractionAndSelectionDetentsUseTheSelectedHeight() {
    struct Fixture: View {
      @State var presented = true
      @State var detent = PresentationDetent.fraction(0.75)
      var body: some View {
        Text("Root").sheet(isPresented: $presented) {
          Text("Sheet").presentationDetents([.medium, .fraction(0.75)], selection: $detent)
        }
      }
    }
    let sheet = all(FiberTree(Fixture()).renderNode) { $0.classes.contains("sheet-panel") }.first
    #expect(sheet?.styles["--presentation-detent-height"] == "calc(100dvh * 0.75)")
  }

  @Test
  func customButtonStyleReceivesPressedStateFromHostEvents() {
    let log = PressLog()
    struct Screen: View {
      let log: PressLog
      var body: some View { Button("Press") {}.buttonStyle(RecordingPressStyle(log: log)) }
    }
    let tree = FiberTree(Screen(log: log))
    let button = tree.findNode(withEvent: "pressed")
    #expect(button?.attributes["data-press-tracking"] == "true")
    #expect(log.values.last == false)
    tree.dispatch(event: "pressed", value: "true", on: button)
    #expect(tree.renderNode.htmlDescription.contains("opacity: 0.5"))
    #expect(log.values.last == true)
    tree.dispatch(event: "pressed", value: "false", on: tree.findNode(withEvent: "pressed", in: tree.renderNode))
    #expect(tree.renderNode.htmlDescription.contains("opacity: 1"))
    #expect(log.values.last == false)
    #expect(log.enabled.allSatisfy { $0 })
  }

  @Test
  func disabledCustomStyledButtonSeesDisabledEnvironmentAndNoPressEvents() {
    let log = PressLog()
    let tree = FiberTree(Button("Press") {}.buttonStyle(RecordingPressStyle(log: log)).disabled(true))
    #expect(tree.findNode(withEvent: "pressed") == nil)
    #expect(log.enabled.last == false)
  }

  @Test
  func primitiveStyleTriggerDrivesTheNativeButtonWithoutNestedButtons() {
    var count = 0
    let tree = FiberTree(Button("Run") { count += 1 }.buttonStyle(DoubleTapStyle()))
    let buttons = all(tree.renderNode) { $0.kind == .element("button") }
    #expect(buttons.count == 1)
    tree.dispatch(event: "click", on: buttons[0])
    #expect(count == 1)
  }
}
