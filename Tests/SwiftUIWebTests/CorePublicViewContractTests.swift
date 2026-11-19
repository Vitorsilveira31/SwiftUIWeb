import Foundation
import Testing
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

private struct OpaquePickerSelection: Hashable, CustomStringConvertible {
  let value: String
  var description: String { "opaque-\(value)" }
}

@Suite(.processGlobalState)
@MainActor
struct CorePublicViewContractTests {
  @Test
  func bodyBackedViewsErasureAndGenericHTMLElementsRenderContent() throws {
    struct BodyBacked: View {
      var body: some View { Text("Body-backed content") }
    }

    #expect(StaticHTMLFiberRenderer().render(BodyBacked()).contains("Body-backed content"))
    #expect(BodyBacked()._render(in: _RenderContext()).htmlDescription.contains("Body-backed content"))
    #expect(StaticHTMLFiberRenderer().render(Text("Erased").eraseToAnyView()).contains("Erased"))
    let closureErased = AnyView { Text("Builder-erased") }
    #expect(StaticHTMLFiberRenderer().render(closureErased).contains("Builder-erased"))
    #expect(closureErased._render(in: _RenderContext()).htmlDescription.contains("Builder-erased"))
    #expect(FiberTree(AnyView { BodyBacked() }).renderNode.htmlDescription.contains("Body-backed content"))

    let section = StaticHTMLFiberRenderer().render(
      HTMLElement(tag: "section", attributes: ["data-section": "account"]) {
        Text("Generic child")
      }
    )
    #expect(section.contains("<section"))
    #expect(section.contains("data-section=\"account\""))
    #expect(section.contains("Generic child"))

    let list = StaticHTMLFiberRenderer().render(
      HTMLElement(
        tag: "ul",
        children: [AnyView(Text("First")), AnyView(EmptyView()), AnyView(Text("Second"))]
      )
    )
    #expect(list.contains("First"))
    #expect(list.contains("Second"))
    let first = try #require(list.range(of: "First"))
    let second = try #require(list.range(of: "Second"))
    #expect(first.lowerBound < second.lowerBound)
    #expect(FiberTree(AnyView(Text("Retained primitive"))).renderNode.htmlDescription.contains("Retained primitive"))
  }

  @Test
  func renderNodeStructuralEqualityChecksTheWholeTree() {
    let original = _RenderNode.fragment()
    original.children = [_RenderNode.element("button")]
    original.children[0].attributes["aria-label"] = "Save"
    original.children[0].children = [_RenderNode.text("Save")]

    let equivalent = original.clone()
    #expect(original.shallowEquals(equivalent))
    #expect(original.structuralEquals(equivalent))

    equivalent.children[0].children[0].text = "Delete"
    #expect(original.shallowEquals(equivalent))
    #expect(!original.structuralEquals(equivalent))

    let missingChild = original.clone()
    missingChild.children.removeAll()
    #expect(!original.structuralEquals(missingChild))

    let differentRoot = _RenderNode.text("Save")
    #expect(!original.structuralEquals(differentRoot))

    let sameTask = FiberTree(Text("Task").task(id: "stable") {}).renderNode
    #expect(sameTask.shallowEquals(sameTask.clone()))
    let changedTask = FiberTree(Text("Task").task(id: "replacement") {}).renderNode
    #expect(!sameTask.shallowEquals(changedTask))

    var receivedValue: String?
    let valueHandler = _EventHandler(
      name: "input",
      action: { receivedValue = $0 },
      preventsDefault: true
    )
    valueHandler.valueAction?("typed value")
    #expect(receivedValue == "typed value")
    #expect(valueHandler.preventsDefault)
  }

  @Test
  func accessibilityHostPreferencesAndScenePhasesHaveStableOrdering() {
    let originalMotion = AccessibilityRuntime.reduceMotion
    let originalTransparency = AccessibilityRuntime.reduceTransparency
    defer {
      AccessibilityRuntime.install(
        reduceMotion: originalMotion,
        reduceTransparency: originalTransparency
      )
    }

    AccessibilityRuntime.install(reduceMotion: true, reduceTransparency: true)
    #expect(AccessibilityRuntime.reduceMotion)
    #expect(AccessibilityRuntime.reduceTransparency)
    AccessibilityRuntime.install(reduceMotion: false)
    #expect(!AccessibilityRuntime.reduceMotion)
    #expect(AccessibilityRuntime.reduceTransparency)

    #expect(ScenePhase.background < .inactive)
    #expect(ScenePhase.inactive < .active)
    #expect(ScenePhase.active > .background)

    let defaults = EnvironmentValues()
    #expect(defaults.accessibilityReduceMotion == AccessibilityRuntime.reduceMotion)
    #expect(defaults.accessibilityReduceTransparency == AccessibilityRuntime.reduceTransparency)
    let object = EnvironmentProbe()
    var withObject = defaults
    withObject._setEnvironmentObject(object)
    #expect(withObject._environmentObject(EnvironmentProbe.self) === object)
  }

  private final class EnvironmentProbe {}

  @Test
  func textStacksSpacersAndLinksPreserveSemanticMarkup() {
    let source = "SwiftUI"
    let fragment = source.dropFirst(5)
    let view = VStack(alignment: .leading, spacing: 12) {
      Text(fragment)
      Text(verbatim: "<literal>")
      HStack(spacing: 4) {
        Link("Settings", destination: URL(string: "/settings")!)
        Spacer(minLength: 16)
        Button(action: {}) {
          HStack { Text("Flexible"); Spacer() }
        }
        Link(destination: URL(string: "https://example.test/help")!) {
          Label("Help", systemImage: "questionmark.circle")
        }
      }
      ZStack(alignment: .topLeading) {
        Text("Back")
        Text("Front")
      }
    }

    let html = StaticHTMLFiberRenderer().render(view)
    #expect(html.contains(">UI"))
    #expect(html.contains("&lt;literal&gt;"))
    #expect(html.contains("href=\"/settings\""))
    #expect(html.contains("href=\"https://example.test/help\""))
    #expect(html.contains("data-spacer-min=\"16.0\""))
    #expect(html.contains("data-flexible-width=\"true\""))
    #expect(html.contains("data-layout-kind=\"zstack\""))
    #expect(html.contains("data-layout-alignment=\"start\""))
    #expect(html.contains("data-align-x=\"0\" data-align-y=\"0\""))
  }

  @Test
  func textFieldsExposeEditingSubmitAndDisabledSemantics() throws {
    var value = "draft"
    var editingChanges: [Bool] = []
    var commits = 0
    let binding = Binding<String>(get: { value }, set: { value = $0 })
    let field = TextField(
      "Notes",
      text: binding,
      onEditingChanged: { editingChanges.append($0) },
      onCommit: { commits += 1 }
    )
    let tree = FiberTree(field)
    let input = try #require(tree.findNode(withEvent: "input"))
    tree.dispatch(event: "input", value: "saved note", on: input)
    tree.dispatch(event: "focus", on: input)
    tree.dispatch(event: "blur", on: input)
    tree.dispatch(event: "submit", on: input)

    #expect(value == "saved note")
    #expect(editingChanges == [true, false])
    #expect(commits == 1)
    #expect(input.events["submit"]?.preventsDefault == true)

    let multiline = StaticHTMLFiberRenderer().render(
      TextField("", text: .constant("line one"), prompt: Text("Write a note"), axis: .vertical)
    )
    #expect(multiline.contains("<textarea"))
    #expect(multiline.contains("placeholder=\"Write a note\""))
    #expect(multiline.contains("data-axis=\"vertical\""))

    let disabled = try #require(find(FiberTree(TextField("Locked", text: .constant("x")).disabled(true)).renderNode) {
      $0.attributes["data-control-kind"] == "text-field"
    })
    #expect(disabled.attributes["aria-disabled"] == "true")
    #expect(disabled.events["input"] == nil)

    let explicitPrompt = StaticHTMLFiberRenderer().render(
      TextField("Prompted", text: .constant("draft"), prompt: Text("Type here"))
    )
    #expect(explicitPrompt.contains("placeholder=\"Type here\""))
  }

  @Test
  func linkTintLabelAndUnlabeledStepperConveniencesRenderTheirPublicValues() throws {
    var count = 2
    let tree = FiberTree(
      VStack {
        Link("Help", destination: URL(string: "https://example.test/help")!)
        Link("Fallback", destination: URL(string: "/settings")!)
        Link("Tinted", destination: URL(string: "https://example.test/tinted")!)
          .tint(.purple)
        Label(title: { Text("Custom label") }, icon: { Image(systemName: "gear") })
        Stepper(value: Binding(get: { count }, set: { count = $0 }), step: 2) { Text("Count") }
      }
    )
    let link = try #require(find(tree.renderNode) { $0.attributes["href"] == "https://example.test/tinted" })
    #expect(link.attributes["data-tint"] == Color.purple.cssValue)
    #expect(link.styles["--tint-color"] == Color.purple.cssValue)
    #expect(tree.renderNode.htmlDescription.contains("https://example.test/help"))
    #expect(tree.renderNode.htmlDescription.contains("/settings"))
    #expect(tree.renderNode.htmlDescription.contains("Custom label"))

    let increment = try #require(find(tree.renderNode) { $0.attributes["aria-label"] == "Increase" })
    tree.dispatch(event: "click", on: increment)
    #expect(count == 4)
  }

  @Test
  func labeledContentAcceptsSubstringTitlesAndConstrainedFlexibleButtonLabels() throws {
    let title: Substring = "Connection status".prefix(17)
    let tree = FiberTree(VStack {
      LabeledContent(title) { Text("Connected") }
      Button {} label: {
        HStack {
          Text("Bounded action")
          Spacer()
        }
        .frame(maxWidth: 120)
      }
    })

    let labeledContent = try #require(find(tree.renderNode) {
      $0.classes.contains("labeled-content")
    })
    #expect(tree.renderNode.htmlDescription.contains("Connection status"))
    #expect(tree.renderNode.htmlDescription.contains("Connected"))

    let button = try #require(find(tree.renderNode) {
      $0.attributes["data-control-kind"] == "button"
    })
    #expect(button.attributes["data-flexible-width"] == nil)
    #expect(labeledContent.children.count == 2)
  }

  @Test
  func secureFieldCommitInitializersAndGroupBoxLabeledContentFormsStaySemantic() throws {
    var secret = "draft"
    var commits = 0
    let secureFields = FiberTree(VStack {
      SecureField("Type secret", text: Binding(get: { secret }, set: { secret = $0 })) {
        commits += 1
      }
      SecureField("Commit", text: Binding(get: { secret }, set: { secret = $0 })) {
        commits += 1
      }
    })
    let fields = descendants(of: secureFields.renderNode).filter { $0.attributes["data-control-kind"] == "secure-field" }
    #expect(fields.count == 2)
    #expect(fields[0].attributes["placeholder"] == "Type secret")
    #expect(fields[1].attributes["placeholder"] == "Commit")
    secureFields.dispatch(event: "submit", on: fields[0])
    secureFields.dispatch(event: "submit", on: fields[1])
    #expect(commits == 2)

    let labeled = StaticHTMLFiberRenderer().render(VStack {
      LabeledContent("Wi-Fi", value: "Connected")
      LabeledContent(content: { Text("Home Network") }, label: { Text("Network") })
      GroupBox("Account") { Text("Profile details") }
      GroupBox { Text("Unlabeled content") }
      GroupBox(label: Text("Custom group"), content: { Text("Custom content") })
    })
    #expect(labeled.contains("Wi-Fi"))
    #expect(labeled.contains("Connected"))
    #expect(labeled.contains("Network"))
    #expect(labeled.contains("Profile details"))
    #expect(labeled.contains("Unlabeled content"))
    #expect(labeled.contains("Custom group"))
    #expect(labeled.contains("Custom content"))
  }

  @Test
  func pickerRoundTripsSupportedScalarSelectionsAndIgnoresInvalidValues() throws {
    final class Values {
      var text = "wifi"
      var integer = 7
      var unsigned: UInt = 8
      var decimal = 1.25
      var enabled = true
    }

    struct PickerView: View {
      let values: Values

      var body: some View {
        VStack {
          Picker("Text", selection: Binding(get: { values.text }, set: { values.text = $0 })) {
            Text("Wi-Fi").tag("wifi")
            Text("Ethernet").tag("ethernet")
          }
          Picker("Integer", selection: Binding(get: { values.integer }, set: { values.integer = $0 })) {
            Text("Seven").tag(7)
            Text("Nine").tag(9)
          }
          Picker("Unsigned", selection: Binding(get: { values.unsigned }, set: { values.unsigned = $0 })) {
            Text("Eight").tag(UInt(8))
            Text("Ten").tag(UInt(10))
          }
          Picker("Decimal", selection: Binding(get: { values.decimal }, set: { values.decimal = $0 })) {
            Text("One quarter").tag(1.25)
            Text("Two half").tag(2.5)
          }
          Picker("Enabled", selection: Binding(get: { values.enabled }, set: { values.enabled = $0 })) {
            Text("Yes").tag(true)
            Text("No").tag(false)
          }
        }
      }
    }

    let values = Values()
    let view = PickerView(values: values)
    let tree = FiberTree(view)
    let selects = descendants(of: tree.renderNode).filter { $0.classes.contains("select-menu") }
    #expect(selects.count == 5)
    #expect(selects.map { $0.attributes["aria-label"] } == ["Text", "Integer", "Unsigned", "Decimal", "Enabled"])
    let hostValues = selects.map { $0.children.last?.attributes["value"] ?? "" }
    #expect(hostValues == ["ethernet", "9", "10", "2.5", "false"])
    for (node, value) in zip(selects, hostValues) {
      tree.dispatch(event: "change", value: value, on: node)
    }
    #expect(values.text == "ethernet")
    #expect(values.integer == 9)
    #expect(values.unsigned == 10)
    #expect(values.decimal == 2.5)
    #expect(!values.enabled)

    tree.dispatch(event: "change", value: "not-a-number", on: selects[1])
    tree.dispatch(event: "change", value: "maybe", on: selects[4])
    #expect(values.integer == 9)
    #expect(!values.enabled)
  }

  @Test
  func pickerRoundTripsOpaqueHashableSelectionsUsingRenderedHostTokens() throws {
    final class Values {
      var selection = OpaquePickerSelection(value: "offline")
    }

    struct PickerView: View {
      let values: Values

      var body: some View {
        Picker("Connection", selection: Binding(
          get: { values.selection },
          set: { values.selection = $0 }
        )) {
          Text("Offline").tag(OpaquePickerSelection(value: "offline"))
          Text("Online").tag(OpaquePickerSelection(value: "online"))
        }
      }
    }

    let values = Values()
    let tree = FiberTree(PickerView(values: values))
    let select = try #require(
      descendants(of: tree.renderNode).first { $0.classes.contains("select-menu") }
    )
    #expect(select.htmlDescription.contains("opaque-offline"))

    let online = try #require(
      descendants(of: select).first { $0.attributes["value"] == "opaque-online" }
    )
    tree.dispatch(event: "change", value: try #require(online.attributes["value"]), on: select)

    #expect(values.selection == OpaquePickerSelection(value: "online"))

    tree.dispatch(event: "change", value: "unknown-option", on: select)
    #expect(values.selection == OpaquePickerSelection(value: "online"))
  }

  @Test
  func boundedSpacerFramesDoNotClaimFlexibleWidth() throws {
    let tree = FiberTree(VStack {
      HStack {
        Text("Bounded stack")
        Spacer().frame(maxWidth: 24)
      }
      Button(action: {}) {
        HStack {
          Text("Bounded button")
          Spacer().frame(width: 18)
        }
      }
    })
    let stack = try #require(find(tree.renderNode) { $0.classes.contains("hstack") })
    #expect(stack.attributes["data-flexible-width"] == nil)
    let button = try #require(find(tree.renderNode) { $0.classes.contains("push-button") })
    #expect(button.attributes["data-flexible-width"] == nil)
  }

  @Test
  func textEditorAndSliderKeepStateBindingsAndDisabledBehavior() throws {
    struct EditorView: View {
      @State var text = "draft"
      var body: some View { TextEditor(text: $text) }
    }

    let editorView = EditorView()
    let editorTree = FiberTree(editorView)
    let editor = try #require(find(editorTree.renderNode) {
      $0.attributes["data-control-kind"] == "text-editor"
    })
    #expect(editor.kind == .element("textarea"))
    #expect(editor.attributes["aria-label"] == "Text editor")
    #expect(editor.htmlDescription.contains("draft"))
    editorTree.dispatch(event: "input", value: "saved", on: editor)
    #expect(editorTree.renderNode.htmlDescription.contains("saved"))

    let disabledEditor = try #require(find(FiberTree(TextEditor(text: .constant("read only")).disabled(true)).renderNode) {
      $0.attributes["data-control-kind"] == "text-editor"
    })
    #expect(disabledEditor.attributes["disabled"] == "disabled")
    #expect(disabledEditor.attributes["aria-disabled"] == "true")
    #expect(disabledEditor.events["input"] == nil)

    struct SliderView: View {
      @State var value = 5.0
      var body: some View {
        VStack {
          Slider(value: $value, in: 0...10, step: 0.5)
          Slider(value: $value, in: 4...4)
        }
      }
    }

    let sliderView = SliderView()
    let sliderTree = FiberTree(sliderView)
    let sliders = descendants(of: sliderTree.renderNode).filter {
      $0.attributes["data-control-kind"] == "slider"
    }
    #expect(sliders.count == 2)
    #expect(sliders[0].attributes["aria-label"] == "Value")
    #expect(sliders[0].attributes["min"] == "0")
    #expect(sliders[0].attributes["max"] == "10")
    #expect(sliders[0].attributes["step"] == "0.5")
    #expect(sliders[0].styles["width"] == "100%")
    #expect(sliders[0].leafBindings.count == 3)
    #expect(sliders[0].leafBindings.map { $0.value() } == ["5", "5", "50%"])

    sliderTree.dispatch(event: "input", value: "7.5", on: sliders[0])
    #expect(sliders[0].leafBindings.map { $0.value() } == ["7.5", "7.5", "75%"])
    sliderTree.dispatch(event: "input", value: "NaN", on: sliders[0])
    sliderTree.dispatch(event: "input", value: "infinity", on: sliders[0])
    #expect(sliders[0].leafBindings.first?.value() == "7.5")

    #expect(sliders[1].styles["--val"] == nil)
    #expect(sliders[1].leafBindings.last?.value() == "")
    let disabledSlider = try #require(find(FiberTree(Slider(value: .constant(0.5)).disabled(true)).renderNode) {
      $0.attributes["data-control-kind"] == "slider"
    })
    #expect(disabledSlider.attributes["disabled"] == "disabled")
    #expect(disabledSlider.attributes["aria-disabled"] == "true")
    #expect(disabledSlider.events["input"] == nil)
  }

  @Test
  func formControlsUpdateTheirBindingsAndKeepDisabledValuesAccessible() throws {
    struct SettingsForm: View {
      @State var network = "wifi"
      @State var accent = Color.blue
      @State var remember = false
      @State var password = "initial-secret"
      @State var note = "draft"

      var body: some View {
        Form {
          Section(content: {
            Picker("Network", selection: $network) {
              Option("Wi-Fi", value: "wifi")
              Option("Bluetooth", value: "bluetooth")
            }
            ColorPicker("Accent", selection: $accent, supportsOpacity: false)
            Toggle("Remember", isOn: $remember)
            SecureField(text: $password, prompt: Text("Password")) { EmptyView() }
            TextField("Notes", text: $note, prompt: Text("Write a note"))
          }, header: {
            Text("Connection")
          }, footer: {
            Text("Changes are saved")
          })
        }
      }
    }

    let view = SettingsForm()
    let tree = FiberTree(view)
    let picker = try #require(find(tree.renderNode) {
      $0.attributes["data-control-kind"] == "picker"
    })
    let select = try #require(find(picker) { $0.kind == .element("select") })
    #expect(select.attributes["aria-label"] == "Network")
    #expect(select.leafBindings.count == 1)
    #expect(select.leafBindings[0].value() == "wifi")
    tree.dispatch(event: "change", value: "bluetooth", on: select)
    #expect(select.leafBindings[0].value() == "bluetooth")
    #expect(tree.renderNode.htmlDescription.contains("selected=\"selected\""))

    let color = try #require(find(tree.renderNode) { $0.attributes["type"] == "color" })
    #expect(color.attributes["data-supports-opacity"] == "false")
    #expect(color.leafBindings.count == 1)
    tree.dispatch(event: "input", value: "#123456", on: color)
    #expect(color.leafBindings[0].value() == "#123456")

    let toggle = try #require(find(tree.renderNode) {
      $0.attributes["data-control-kind"] == "toggle"
    })
    let checkbox = try #require(find(toggle) { $0.attributes["type"] == "checkbox" })
    tree.dispatch(event: "change", value: "yes", on: checkbox)
    let checked = try #require(find(tree.renderNode) { $0.attributes["role"] == "switch" })
    #expect(checked.attributes["aria-checked"] == "true")
    tree.dispatch(event: "change", value: "no", on: checked)
    let unchecked = try #require(find(tree.renderNode) { $0.attributes["role"] == "switch" })
    #expect(unchecked.attributes["aria-checked"] == "false")

    let password = try #require(find(tree.renderNode) {
      $0.attributes["data-control-kind"] == "secure-field"
    })
    #expect(password.attributes["placeholder"] == "Password")
    #expect(password.attributes["value"] == nil)
    #expect(password.leafBindings.count == 1)
    #expect(!tree.renderNode.htmlDescription.contains("initial-secret"))
    tree.dispatch(event: "input", value: "updated-secret", on: password)
    #expect(!tree.renderNode.htmlDescription.contains("updated-secret"))

    let note = try #require(find(tree.renderNode) {
      $0.attributes["data-control-kind"] == "text-field"
    })
    #expect(note.attributes["placeholder"] == "Write a note")
    #expect(note.leafBindings.count == 1)
    tree.dispatch(event: "input", value: "updated note", on: note)
    #expect(note.leafBindings[0].value() == "updated note")

    let disabled = FiberTree(
      Form {
        Picker("Locked", selection: .constant("fixed")) {
          Option("Fixed", value: "fixed")
        }
        .disabled(true)
        ColorPicker("Locked color", selection: .constant(.red)).disabled(true)
        Toggle("Locked toggle", isOn: .constant(false)).disabled(true)
        SecureField("Locked secret", text: .constant("private")).disabled(true)
      }
    )
    let disabledSelect = try #require(find(disabled.renderNode) { $0.kind == .element("select") })
    #expect(disabledSelect.attributes["disabled"] == "disabled")
    #expect(disabledSelect.attributes["aria-disabled"] == "true")
    #expect(disabledSelect.events["change"] == nil)
    let disabledColor = try #require(find(disabled.renderNode) { $0.attributes["type"] == "color" })
    #expect(disabledColor.attributes["disabled"] == "disabled")
    #expect(disabledColor.events["change"] == nil)
    let disabledToggle = try #require(find(disabled.renderNode) { $0.attributes["role"] == "switch" })
    #expect(disabledToggle.attributes["disabled"] == "disabled")
    #expect(disabledToggle.events["change"] == nil)
    let disabledPassword = try #require(find(disabled.renderNode) {
      $0.attributes["data-control-kind"] == "secure-field"
    })
    #expect(disabledPassword.attributes["disabled"] == "disabled")
    #expect(disabledPassword.events["input"] == nil)
  }

  @Test
  func secureFieldsKeepSecretsOutOfRenderNodesAndSupportSubmission() throws {
    var secret = "initial-secret"
    var submissions = 0
    let binding = Binding<String>(get: { secret }, set: { secret = $0 })
    let field = SecureField("Password", text: binding) { submissions += 1 }
    let tree = FiberTree(field)
    let input = try #require(tree.findNode(withEvent: "input"))

    #expect(input.attributes["type"] == "password")
    #expect(input.attributes["placeholder"] == "Password")
    #expect(input.attributes["value"] == nil)
    #expect(!tree.renderNode.htmlDescription.contains("initial-secret"))

    tree.dispatch(event: "input", value: "updated-secret", on: input)
    tree.dispatch(event: "submit", on: input)
    #expect(secret == "updated-secret")
    #expect(submissions == 1)
    #expect(input.events["submit"]?.preventsDefault == true)

    let disabled = try #require(find(FiberTree(SecureField("Secret", text: .constant("" )).disabled(true)).renderNode) {
      $0.attributes["data-control-kind"] == "secure-field"
    })
    #expect(disabled.attributes["disabled"] == "disabled")
    #expect(disabled.events["input"] == nil)
  }

  @Test
  func steppersClampFloatingValuesAndRunActionClosures() throws {
    var volume = 0.5
    let binding = Binding<Double>(get: { volume }, set: { volume = $0 })
    let bounded = Stepper("Volume", value: binding, in: 0.0...1.0, step: 0.25)
    let tree = FiberTree(bounded)
    let buttons = descendants(of: tree.renderNode).filter { $0.kind == .element("button") }
    #expect(buttons.count == 2)
    #expect(tree.renderNode.htmlDescription.contains("aria-valuenow=\"0.5\""))

    tree.dispatch(event: "click", on: buttons[1])
    #expect(volume == 0.75)
    tree.dispatch(event: "click", on: buttons[1])
    #expect(volume == 1)
    _ = tree.update(bounded)
    let updatedButtons = descendants(of: tree.renderNode).filter { $0.kind == .element("button") }
    #expect(updatedButtons[1].attributes["disabled"] == "disabled")

    var increments = 0
    var decrements = 0
    let actions = FiberTree(Stepper("Actions", onIncrement: { increments += 1 }, onDecrement: { decrements += 1 }))
    let actionButtons = descendants(of: actions.renderNode).filter { $0.kind == .element("button") }
    actions.dispatch(event: "click", on: actionButtons[0])
    actions.dispatch(event: "click", on: actionButtons[1])
    #expect(decrements == 1)
    #expect(increments == 1)

    var count = 3
    let unbounded = FiberTree(Stepper(value: Binding(get: { count }, set: { count = $0 }), step: 2) {
      Text("Count")
    })
    let unboundedButtons = descendants(of: unbounded.renderNode).filter { $0.kind == .element("button") }
    unbounded.dispatch(event: "click", on: unboundedButtons[1])
    unbounded.dispatch(event: "click", on: unboundedButtons[0])
    #expect(count == 3)

    let invalidStep = FiberTree(Stepper(value: Binding(get: { count }, set: { count = $0 }), in: 0...10, step: 0) { EmptyView() })
    let invalidButtons = descendants(of: invalidStep.renderNode).filter { $0.kind == .element("button") }
    #expect(invalidButtons.allSatisfy { $0.attributes["disabled"] == "disabled" })
  }

  @Test
  func unlabeledStepperInitializersPreserveIntegerAndFloatingPointContracts() throws {
    var integer = 1
    let integerBinding = Binding<Int>(get: { integer }, set: { integer = $0 })
    let boundedInteger = Stepper(value: integerBinding, in: 0...2, step: 1) { EmptyView() }
    let integerTree = FiberTree(boundedInteger)
    let integerControl = try #require(find(integerTree.renderNode) {
      $0.attributes["role"] == "spinbutton"
    })
    #expect(integerControl.attributes["aria-valuenow"] == "1")
    #expect(integerControl.attributes["aria-valuemin"] == "0")
    #expect(integerControl.attributes["aria-valuemax"] == "2")
    let integerButtons = descendants(of: integerTree.renderNode).filter {
      $0.kind == .element("button")
    }
    integerTree.dispatch(event: "click", on: integerButtons[1])
    #expect(integer == 2)
    _ = integerTree.update(boundedInteger)
    let maxButtons = descendants(of: integerTree.renderNode).filter {
      $0.kind == .element("button")
    }
    #expect(maxButtons[1].attributes["aria-disabled"] == "true")
    integerTree.dispatch(event: "click", on: maxButtons[0])
    #expect(integer == 1)

    var floating = 0.5
    let floatingBinding = Binding<Double>(get: { floating }, set: { floating = $0 })
    let boundedFloating = Stepper(value: floatingBinding, in: 0.0...1.0, step: 0.25) { EmptyView() }
    let floatingTree = FiberTree(boundedFloating)
    let floatingValue = try #require(find(floatingTree.renderNode) {
      $0.attributes["role"] == "spinbutton"
    })
    #expect(floatingValue.attributes["aria-valuenow"] == "0.5")
    #expect(floatingValue.attributes["aria-valuemin"] == "0.0")
    #expect(floatingValue.attributes["aria-valuemax"] == "1.0")
    let floatingButtons = descendants(of: floatingTree.renderNode).filter {
      $0.kind == .element("button")
    }
    floatingTree.dispatch(event: "click", on: floatingButtons[0])
    #expect(floating == 0.25)

    var unbounded = 1.0
    let unboundedBinding = Binding<Double>(get: { unbounded }, set: { unbounded = $0 })
    let unboundedTree = FiberTree(Stepper(value: unboundedBinding, step: 0.5) { EmptyView() })
    let unboundedButtons = descendants(of: unboundedTree.renderNode).filter {
      $0.kind == .element("button")
    }
    unboundedTree.dispatch(event: "click", on: unboundedButtons[1])
    #expect(unbounded == 1.5)

    let nonPositiveStep = FiberTree(Stepper(value: unboundedBinding, step: 0.0) { EmptyView() })
    let disabledButtons = descendants(of: nonPositiveStep.renderNode).filter {
      $0.kind == .element("button")
    }
    #expect(disabledButtons.allSatisfy { $0.attributes["aria-disabled"] == "true" })
  }

  @Test
  func asyncImageConvenienceInitializersResolvePlaceholderAndLoadedImage() throws {
    let url = URL(string: "https://example.test/cover.png")!
    let placeholder = AsyncImage(url: url, scale: 2) { image in image } placeholder: {
      Text("Waiting")
    }
    let placeholderTree = FiberTree(placeholder)
    #expect(placeholderTree.renderNode.htmlDescription.contains("Waiting"))
    #expect(placeholderTree.renderNode.htmlDescription.contains("data-scale=\"2\""))
    let placeholderLoader = try #require(placeholderTree.findNode(withEvent: "load"))
    placeholderTree.dispatch(event: "load", on: placeholderLoader)
    _ = placeholderTree.update(placeholder)
    #expect(placeholderTree.renderNode.htmlDescription.contains("cover.png"))
    #expect(!placeholderTree.renderNode.htmlDescription.contains("Waiting"))

    let contentTree = FiberTree(AsyncImage(url: url, content: { image in
      image.resizable().scaledToFit()
    }, placeholder: {
      ProgressView("Loading cover")
    }))
    #expect(contentTree.renderNode.htmlDescription.contains("Loading cover"))
    let contentLoader = try #require(contentTree.findNode(withEvent: "load"))
    contentTree.dispatch(event: "load", on: contentLoader)
    #expect(contentTree.renderNode.htmlDescription.contains("cover.png"))
    #expect(!contentTree.renderNode.htmlDescription.contains("Loading cover"))

    let defaultContent = AsyncImage(url: url, scale: 1.5)
    let defaultContentTree = FiberTree(defaultContent)
    #expect(defaultContentTree.renderNode.htmlDescription.contains("spinner-ring"))
    #expect(defaultContentTree.renderNode.htmlDescription.contains("data-scale=\"1.5\""))
    let defaultLoader = try #require(defaultContentTree.findNode(withEvent: "load"))
    defaultContentTree.dispatch(event: "load", on: defaultLoader)
    _ = defaultContentTree.update(defaultContent)
    #expect(defaultContentTree.renderNode.htmlDescription.contains("cover.png"))

    let failureContent = AsyncImage(url: url, content: { image in
      Text("Loaded: \(image.source)")
    }, placeholder: {
      Text("Image unavailable")
    })
    let failedTree = FiberTree(failureContent)
    let errorLoader = try #require(failedTree.findNode(withEvent: "error"))
    failedTree.dispatch(event: "error", on: errorLoader)
    _ = failedTree.update(failureContent)
    #expect(failedTree.renderNode.htmlDescription.contains("Image unavailable"))
    #expect(!failedTree.renderNode.htmlDescription.contains("Loaded:"))

    let failureAsEmpty = AsyncImage(url: url) { phase in
      if let image = phase.image {
        image
      } else if phase.error != nil {
        EmptyView()
      } else {
        Text("Still loading")
      }
    }
    let failureAsEmptyTree = FiberTree(failureAsEmpty)
    let errorAsEmptyLoader = try #require(failureAsEmptyTree.findNode(withEvent: "error"))
    failureAsEmptyTree.dispatch(event: "error", on: errorAsEmptyLoader)
    _ = failureAsEmptyTree.update(failureAsEmpty)
    #expect(!failureAsEmptyTree.renderNode.htmlDescription.contains("Still loading"))

    let missingURL = StaticHTMLFiberRenderer().render(AsyncImage(url: Optional<URL>.none))
    #expect(missingURL.isEmpty)
  }

  @Test
  func colorPickerDisabledStateAndSearchEmptyStateAreAccessible() throws {
    var selection = Color.blue
    let binding = Binding<Color>(get: { selection }, set: { selection = $0 })
    let enabledTree = FiberTree(ColorPicker(selection: binding, label: { Text("Accent color") }))
    let input = try #require(enabledTree.findNode(withEvent: "change"))
    #expect(input.attributes["type"] == "color")
    #expect(input.attributes["value"] == "#007aff")
    enabledTree.dispatch(event: "input", value: "#123456", on: input)
    #expect(selection.cssValue == "#123456")

    let disabledTree = FiberTree(ColorPicker("Accent", selection: binding).disabled(true))
    let disabledInput = try #require(find(disabledTree.renderNode) { $0.attributes["type"] == "color" })
    #expect(disabledInput.attributes["disabled"] == "disabled")
    #expect(disabledInput.events["change"] == nil)

    let emptyState = StaticHTMLFiberRenderer().render(
      ContentUnavailableView.search(text: "oranges")
    )
    #expect(emptyState.contains("No Results for “oranges”"))
    #expect(emptyState.contains("Check the spelling or try a new search."))
    #expect(emptyState.contains("magnifyingglass"))
  }

  @Test
  func gridAndDisclosureViewsExposeAxisAndExpansionContracts() throws {
    let grid = StaticHTMLFiberRenderer().render(
      LazyHGrid(rows: [GridItem(.fixed(36)), GridItem(.adaptive(minimum: 80)), GridItem(.flexible(minimum: 24))], spacing: 10) {
        Text("one")
        Text("two")
      }
    )
    #expect(grid.contains("hgrid"))
    #expect(grid.contains("data-lazy=\"horizontal\""))
    #expect(grid.contains("grid-template-rows: 36px repeat(auto-fit, minmax(80px, 1fr)) minmax(24px, 1fr)"))

    var expanded = false
    let disclosure = DisclosureGroup("Details", isExpanded: Binding(get: { expanded }, set: { expanded = $0 })) {
      Text("More information")
    }
    let tree = FiberTree(disclosure)
    let summary = try #require(find(tree.renderNode) { $0.kind == .element("summary") })
    #expect(summary.attributes["aria-expanded"] == "false")
    tree.dispatch(event: "click", on: summary)
    #expect(expanded)
    #expect(tree.update(disclosure).isEmpty == false)
    #expect(tree.renderNode.htmlDescription.contains("aria-expanded=\"true\""))
  }

  @Test
  func sectionsListsMenusAndSummaryViewsKeepTheirSemanticContent() throws {
    struct Row { let key: String; let title: String }
    let rows = [Row(key: "first", title: "First row"), Row(key: "second", title: "Second row")]
    let list = List(rows, id: \.key) { row in Text(row.title) }
    let listHTML = StaticHTMLFiberRenderer().render(list)
    #expect(listHTML.contains("<ul"))
    #expect(listHTML.contains("First row"))
    #expect(listHTML.contains("Second row"))

    let form = StaticHTMLFiberRenderer().render(Form {
      Section(content: {
        LabeledContent("Status", value: "Ready")
        DisclosureGroup(content: { Text("Advanced values") }, label: { Text("Advanced") })
      }, header: {
        Text("General")
      }, footer: {
        Text("Managed by your organization")
      })
      GroupBox(content: {
        Text("Account details")
      }, label: {
        Text("Account")
      })
      GroupBox("About") { Text("Version 1") }
      Menu(content: { Button("Refresh") {} }, label: { Text("Actions") })
      ContentUnavailableView("Offline", systemImage: "wifi.slash")
      Gauge(value: 3, in: 0...4, label: { Text("Capacity") }, currentValueLabel: {
        Text("3 of 4")
      })
      Gauge(value: 1, in: 0...5, label: { Text("Battery") }, currentValueLabel: {
        Text("1")
      }, minimumValueLabel: {
        Text("Empty")
      }, maximumValueLabel: {
        Text("Full")
      })
    })
    #expect(form.contains("<form"))
    #expect(form.contains("section-heading"))
    #expect(form.contains("Managed by your organization"))
    #expect(form.contains("role=\"term\""))
    #expect(form.contains("role=\"definition\""))
    #expect(form.contains("group-box"))
    #expect(form.contains("Account details"))
    #expect(form.contains("menu-popup"))
    #expect(form.contains("aria-haspopup=\"menu\""))
    #expect(form.contains("Offline"))
    #expect(form.contains("Capacity"))
    #expect(form.contains("Empty"))
    #expect(form.contains("Full"))

    let collapsed = try #require(find(FiberTree(DisclosureGroup("Details") {
      Text("Collapsed details")
    }).renderNode) { $0.kind == .element("details") })
    #expect(collapsed.attributes["open"] == nil)
    let disabledDisclosure = try #require(find(FiberTree(
      DisclosureGroup("Locked", isExpanded: .constant(false)) { Text("Hidden") }.disabled(true)
    ).renderNode) { $0.kind == .element("summary") })
    #expect(disabledDisclosure.attributes["aria-disabled"] == "true")
    #expect(disabledDisclosure.events["click"] == nil)
  }

  @Test
  func tablesRenderCustomColumnsAndAUsefulRowFallback() {
    struct Row: Identifiable, CustomStringConvertible {
      let id: Int
      let title: String
      let available: Bool
      var description: String { "fallback-row-\(id)" }
    }
    let rows = [
      Row(id: 1, title: "Studio", available: true),
      Row(id: 2, title: "Archive", available: false)
    ]
    let table = Table(rows) {
      TableColumn("Title", value: \.title)
      TableColumn("Availability") { row in
        if row.available { Text("Available") } else { Text("Unavailable") }
      }
    }
    let html = StaticHTMLFiberRenderer().render(table)
    #expect(html.contains("data-table-column=\"Title\""))
    #expect(html.contains("data-table-column=\"Availability\""))
    #expect(html.contains("<td>Studio</td>"))
    #expect(html.contains("<td>Available</td>"))
    #expect(html.contains("<td>Unavailable</td>"))
    #expect(html.contains("data-row-id=\""))

    struct ValuesRow: Identifiable {
      let id: Int
      let int: Int
      let uint: UInt
      let double: Double
      let bool: Bool
    }
    // Apple's `value:` columns over non-String values are sortable and need a content closure.
    let valuesTable = StaticHTMLFiberRenderer().render(Table([
      ValuesRow(id: 1, int: 7, uint: 8, double: 1.25, bool: true)
    ]) {
      TableColumn("Int", value: \.int) { row in Text("\(row.int)") }
      TableColumn("UInt", value: \.uint) { row in Text("\(row.uint)") }
      TableColumn("Double", value: \.double) { row in Text("\(row.double)") }
    })
    #expect(valuesTable.contains("<td>7</td>"))
    #expect(valuesTable.contains("<td>8</td>"))
    #expect(valuesTable.contains("<td>1.25</td>"))
    let booleanTable = StaticHTMLFiberRenderer().render(Table([
      ValuesRow(id: 2, int: 0, uint: 0, double: 0, bool: true)
    ]) {
      TableColumn("Bool") { row in Text(row.bool ? "true" : "false") }
    })
    #expect(booleanTable.contains("<td>true</td>"))
  }

  @Test
  func tableColumnBuilderSupportsEmptyOptionalAndConditionalColumnGroups() {
    struct Row: Identifiable, CustomStringConvertible {
      let id: Int
      var description: String { "row-\(id)" }
    }

    typealias Column = TableColumn<Row, Never, Text, Text>
    let single = TableColumnBuilder<Row, Never>.buildBlock(TableColumn("Single") { (_: Row) in Text("cell") })
    let optional: Column? = TableColumnBuilder<Row, Never>.buildIf(Optional<Column>.none)
    let first: _ConditionalContent<Column, Column> =
      TableColumnBuilder<Row, Never>.buildEither(first: TableColumn("First") { (_: Row) in Text("first") })
    let second: _ConditionalContent<Column, Column> =
      TableColumnBuilder<Row, Never>.buildEither(second: TableColumn("Second") { (_: Row) in Text("second") })
    let three = TableColumnBuilder<Row, Never>.buildBlock(
      TableColumn("One") { (_: Row) in Text("one") },
      TableColumn("Two") { (_: Row) in Text("two") },
      TableColumn("Three") { (_: Row) in Text("three") }
    )

    #expect(optional == nil)
    #expect(single._renderTableColumns(in: _RenderContext()).attributes["data-table-column"] == "Single")
    #expect(first._renderTableColumns(in: _RenderContext()).attributes["data-table-column"] == "First")
    #expect(second._renderTableColumns(in: _RenderContext()).attributes["data-table-column"] == "Second")
    #expect(three._renderTableColumns(in: _RenderContext()).children.map { $0.attributes["data-table-column"] } == ["One", "Two", "Three"])
  }

  @Test
  func emptySceneIsAValidEmptyRootView() {
    #expect(StaticHTMLFiberRenderer().render(EmptyScene()).isEmpty)
  }

  @Test
  func resizableImageStretchesAndAFitKeepsItsRatio() {
    // `resizable()` alone stretches the image to its frame, as in SwiftUI; `scaledToFit` / `scaledToFill` set their fit.
    let stretched = StaticHTMLFiberRenderer().render(Image("ledge.png").resizable().frame(width: 300, height: 200))
    #expect(stretched.contains("object-fit: fill"))
    let fitted = StaticHTMLFiberRenderer().render(Image("ledge.png").resizable().scaledToFit())
    #expect(fitted.contains("object-fit: contain"))
    let filled = StaticHTMLFiberRenderer().render(Image("ledge.png").resizable().scaledToFill())
    #expect(filled.contains("object-fit: cover"))
  }

  @Test
  func stackedTransformsComposeInModifierOrder() {
    // An offset then a scale both apply, the outer one first in the CSS list, as the offset modifier already chains.
    let html = StaticHTMLFiberRenderer().render(Color.red.frame(width: 10, height: 10).offset(y: 540).scaleEffect(0.5))
    #expect(html.contains("scale(0.5) translate(0px, 540px)"))
    let twice = StaticHTMLFiberRenderer().render(Color.red.frame(width: 10, height: 10).scaleEffect(2).rotationEffect(.degrees(0)))
    #expect(twice.contains("rotate(0.0rad) scale(2.0)"))
  }

  @Test
  func swiftUIOwnersOfImageListAndToolbarModifiersKeepTheirBehavior() throws {
    // `resizable`, `interpolation` and `antialiased` are `Image -> Image` in SwiftUI, so they chain in any order.
    let image: Image = Image("donut.png").resizable().interpolation(.none).antialiased(true)
    let html = StaticHTMLFiberRenderer().render(image.scaledToFit())
    #expect(html.contains("data-resizable=\"true\""))
    #expect(html.contains("image-rendering: pixelated") || html.contains("image-rendering:pixelated"))
    #expect(html.contains("object-fit"))

    // `onDelete` / `onMove` belong to dynamic content (`ForEach`), not to every view.
    let rows = ForEach(["Row alpha", "Row beta"], id: \.self) { Text($0) }
    let list = StaticHTMLFiberRenderer().render(List {
      rows.onDelete { _ in }.onMove { _, _ in }
    })
    #expect(list.contains("Row alpha") && list.contains("Row beta"))
    #expect(rows.data == ["Row alpha", "Row beta"])
    // A modifier on the dynamic content keeps its rows: `padding()` is `some View` as in SwiftUI, so check the render.
    let padded = StaticHTMLFiberRenderer().render(List { rows.padding() })
    #expect(padded.contains("Row alpha") && padded.contains("Row beta"))

    // The title menu is toolbar content that renders the principal menu itself.
    let menu = ToolbarTitleMenu { Button("Rename") {} }
    #expect(StaticHTMLFiberRenderer().render(menu).contains("Rename"))
  }

  private func find(_ node: _RenderNode, where predicate: (_RenderNode) -> Bool) -> _RenderNode? {
    if predicate(node) { return node }
    for child in node.children {
      if let match = find(child, where: predicate) { return match }
    }
    return nil
  }

  private func descendants(of node: _RenderNode) -> [_RenderNode] {
    [node] + node.children.flatMap(descendants)
  }
}
