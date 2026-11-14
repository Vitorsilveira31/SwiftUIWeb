import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
struct KeyboardShortcutTests {
  private func nodes(_ node: _RenderNode, where predicate: (_RenderNode) -> Bool) -> [_RenderNode] {
    (predicate(node) ? [node] : []) + node.children.flatMap { nodes($0, where: predicate) }
  }

  @Test
  func keyEquivalentsMatchSwiftUIValuesAndBrowserKeys() {
    #expect(KeyEquivalent.return.character == "\r")
    #expect(KeyEquivalent.escape.character == "\u{1B}")
    #expect(KeyEquivalent.delete.character == "\u{8}")
    #expect(KeyEquivalent.upArrow.character == "\u{F700}")
    let letter: KeyEquivalent = "S"
    #expect(letter._webKeyToken == "s")
    #expect(KeyEquivalent.space._webKeyToken == "Space")
    #expect(KeyEquivalent.deleteForward._webKeyToken == "Delete")
    #expect(KeyEquivalent(_webKey: "ArrowDown") == .downArrow)
    #expect(KeyEquivalent(_webKey: " ") == .space)
    #expect(KeyEquivalent(_webKey: "NumpadEnter") == .return)
    #expect(KeyEquivalent(_webKey: "k") == KeyEquivalent("k"))
    #expect(KeyEquivalent(_webKey: "Shift") == nil)
    #expect(KeyboardShortcut.defaultAction == KeyboardShortcut(.return, modifiers: []))
    #expect(KeyboardShortcut.cancelAction.key == .escape)
    #expect(KeyboardShortcut("n").modifiers == .command)
  }

  @Test
  func buttonPublishesShortcutWithModifiersAndAriaKeyShortcuts() {
    let tree = FiberTree(VStack {
      Button("Save") {}.keyboardShortcut("s", modifiers: [.command, .shift])
      Button("OK") {}.keyboardShortcut(.defaultAction)
      Button("Cancel") {}.keyboardShortcut(.cancelAction)
      Button("Plain") {}
    })
    let buttons = nodes(tree.renderNode) { $0.attributes["data-control-kind"] == "button" }
    #expect(buttons.count == 4)
    #expect(buttons[0].attributes["data-keyboard-shortcut"] == "s|command,shift")
    #expect(buttons[0].attributes["aria-keyshortcuts"] == "Meta+Shift+S")
    #expect(buttons[1].attributes["data-keyboard-shortcut"] == "Enter|")
    #expect(buttons[2].attributes["data-keyboard-shortcut"] == "Escape|")
    #expect(buttons[3].attributes["data-keyboard-shortcut"] == nil)
  }

  @Test
  func disabledButtonsDoNotPublishTheirActionAndNilRemovesAnInheritedShortcut() {
    let tree = FiberTree(VStack {
      Button("Disabled") {}.keyboardShortcut("d").disabled(true)
      VStack { Button("Cleared") {}.keyboardShortcut(nil) }.keyboardShortcut("x")
    })
    let buttons = nodes(tree.renderNode) { $0.attributes["data-control-kind"] == "button" }
    #expect(buttons[0].attributes["disabled"] == "disabled")
    #expect(buttons[0].events["click"] == nil)
    #expect(buttons[1].attributes["data-keyboard-shortcut"] == nil)
  }

  @Test
  func shortcutDoesNotLeakIntoTheLabelOrThePresentedSheet() {
    struct Fixture: View {
      @State private var presented = true
      var body: some View {
        Button { } label: { Button("Inner") {} }
          .keyboardShortcut("k")
          .sheet(isPresented: $presented) { Button("Sheet button") {} }
      }
    }
    let tree = FiberTree(Fixture())
    let shortcutNodes = nodes(tree.renderNode) { $0.attributes["data-keyboard-shortcut"] != nil }
    #expect(shortcutNodes.count == 1)
  }

  @Test
  func toggleShortcutIsPublishedOnTheActivationElement() {
    let tree = FiberTree(Toggle("Bold", isOn: .constant(false)).keyboardShortcut("b"))
    let input = nodes(tree.renderNode) { $0.attributes["type"] == "checkbox" }.first
    #expect(input?.attributes["data-keyboard-shortcut"] == "b|command")
  }
}
