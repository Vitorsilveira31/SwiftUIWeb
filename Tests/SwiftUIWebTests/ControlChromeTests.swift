import Testing
import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
struct ControlChromeTests {
  @Test
  func defaultControlsKeepFrameworkChrome() throws {
    let tree = FiberTree(VStack {
      TextField("Title", text: .constant(""))
      TextEditor(text: .constant("Notes"))
      Picker("Format", selection: .constant("a")) { Text("A").tag("a") }
    })
    #expect(findNode(tree.renderNode) { $0.attributes["data-field-chrome"] != nil } == nil)
    let picker = try #require(findNode(tree.renderNode) { $0.classes.contains("picker-control") })
    #expect(picker.children.contains { $0.classes.contains("picker-label") })
  }

  @Test
  func plainTextFieldStyleIsInheritedByTextAndSecureFields() throws {
    let tree = FiberTree(VStack {
      TextField("Search", text: .constant(""))
      SecureField("Password", text: .constant(""))
    }.textFieldStyle(.plain))
    let field = try #require(findNode(tree.renderNode) { $0.attributes["data-control-kind"] == "text-field" })
    let secure = try #require(findNode(tree.renderNode) { $0.attributes["data-control-kind"] == "secure-field" })
    #expect(field.attributes["data-field-chrome"] == "plain")
    #expect(secure.attributes["data-field-chrome"] == "plain")

    let direct = FiberTree(TextField("Direct", text: .constant("")).textFieldStyle(.plain))
    #expect(findNode(direct.renderNode) { $0.attributes["data-control-kind"] == "text-field" }?
      .attributes["data-field-chrome"] == "plain")
    let rounded = FiberTree(TextField("Rounded", text: .constant("")).textFieldStyle(.roundedBorder))
    #expect(findNode(rounded.renderNode) { $0.attributes["data-field-chrome"] != nil } == nil)
  }

  @Test
  func textEditorWithoutScrollContentBackgroundIsChromeLess() throws {
    let tree = FiberTree(TextEditor(text: .constant("Notes")).scrollContentBackground(.hidden))
    let editor = try #require(findNode(tree.renderNode) { $0.attributes["data-control-kind"] == "text-editor" })
    #expect(editor.attributes["data-field-chrome"] == "plain")
  }

  @Test
  func menuPickerWithHiddenLabelsRendersAChromeLessSelect() throws {
    let plain = FiberTree(Picker("Format", selection: .constant("a")) {
      Text("A").tag("a")
      Text("B").tag("b")
    }.pickerStyle(.menu).labelsHidden())
    let picker = try #require(findNode(plain.renderNode) { $0.classes.contains("picker-control") })
    #expect(picker.attributes["data-field-chrome"] == "plain")
    #expect(picker.children.count == 1)
    let select = try #require(picker.children.first)
    #expect(select.kind == .element("select"))
    #expect(select.attributes["data-field-chrome"] == "plain")
    #expect(select.attributes["aria-label"] == "Format")

    let hiddenOnly = FiberTree(Picker("Format", selection: .constant("a")) { Text("A").tag("a") }.labelsHidden())
    let hiddenPicker = try #require(findNode(hiddenOnly.renderNode) { $0.classes.contains("picker-control") })
    #expect(hiddenPicker.attributes["data-field-chrome"] == nil)
    #expect(!hiddenPicker.children.contains { $0.classes.contains("picker-label") })

    let menuOnly = FiberTree(Picker("Format", selection: .constant("a")) { Text("A").tag("a") }.pickerStyle(.menu))
    let menuPicker = try #require(findNode(menuOnly.renderNode) { $0.classes.contains("picker-control") })
    #expect(menuPicker.attributes["data-field-chrome"] == nil)
    #expect(menuPicker.children.contains { $0.classes.contains("picker-label") })
  }

  @Test
  func compactDatePickerWithHiddenLabelsIsANativeChromeLessInput() throws {
    let date = FiberTree(DatePicker("Release", selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date)
      .labelsHidden()
      .datePickerStyle(.compact))
    let picker = try #require(findNode(date.renderNode) { $0.attributes["data-control-kind"] == "date-picker" })
    #expect(picker.attributes["data-field-chrome"] == "plain")
    #expect(!picker.children.contains { $0.classes.contains("date-picker-label") })
    #expect(findNode(picker) { $0.classes.contains("date-picker-trigger") } == nil)
    let input = try #require(findNode(picker) { $0.attributes["data-control-kind"] == "date-input" })
    #expect(input.attributes["type"] == "date")
    #expect(input.attributes["data-field-chrome"] == "plain")
    #expect(input.classes.contains("date-input-native"))
    #expect(input.attributes["aria-label"] == "Release")

    let time = FiberTree(DatePicker("Time", selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .hourAndMinute)
      .labelsHidden()
      .datePickerStyle(.compact))
    #expect(findNode(time.renderNode) { $0.attributes["data-control-kind"] == "date-input" }?.attributes["type"] == "time")

    let standard = FiberTree(DatePicker("Release", selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date))
    #expect(findNode(standard.renderNode) { $0.classes.contains("date-picker-trigger") } != nil)
    #expect(findNode(standard.renderNode) { $0.attributes["data-field-chrome"] != nil } == nil)
  }
}

private func findNode(_ node: _RenderNode, matching predicate: (_RenderNode) -> Bool) -> _RenderNode? {
  if predicate(node) { return node }
  for child in node.children {
    if let match = findNode(child, matching: predicate) { return match }
  }
  return nil
}
