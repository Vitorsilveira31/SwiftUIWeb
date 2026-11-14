@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// Keyboard modifiers exposed to SwiftUI-shaped key handlers.
package struct SwiftUIWebKeyEvent: Hashable, Sendable {
  package let code: String
  package let shift: Bool
  package let control: Bool
  package let command: Bool
  package let option: Bool
  package let isRepeat: Bool
  package let isEditable: Bool

  package init(code: String, shift: Bool = false, control: Bool = false, command: Bool = false, option: Bool = false, isRepeat: Bool = false, isEditable: Bool = false) {
    self.code = code
    self.shift = shift
    self.control = control
    self.command = command
    self.option = option
    self.isRepeat = isRepeat
    self.isEditable = isEditable
  }

  init(payload: String) {
    let fields = payload.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    code = fields.first ?? ""
    shift = fields[safe: 1] == "1"
    control = fields[safe: 2] == "1"
    command = fields[safe: 3] == "1"
    option = fields[safe: 4] == "1"
    isRepeat = fields[safe: 5] == "1"
    isEditable = fields[safe: 6] == "1"
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

package extension View {
  /// Receives key presses while this view is the nearest registered keyboard
  /// event owner. Editable controls are identified in the event value so the
  /// application can leave text editing and browser shortcuts untouched.
  nonisolated func onKeyDown(preventsDefault: Bool = false, perform action: @escaping @MainActor (SwiftUIWebKeyEvent) -> Void) -> ModifiedContent<Self, KeyboardEventModifier> {
    modifier(KeyboardEventModifier(name: "keyDown", preventsDefault: preventsDefault, action: action))
  }

  nonisolated func onKeyUp(perform action: @escaping @MainActor (SwiftUIWebKeyEvent) -> Void) -> ModifiedContent<Self, KeyboardEventModifier> {
    modifier(KeyboardEventModifier(name: "keyUp", preventsDefault: false, action: action))
  }
}

package nonisolated struct KeyboardEventModifier: ViewModifier {
  package let name: String
  package let preventsDefault: Bool
  private let action: @MainActor (SwiftUIWebKeyEvent) -> Void

  package init(name: String, preventsDefault: Bool = false, action: @escaping @MainActor (SwiftUIWebKeyEvent) -> Void) {
    self.name = name
    self.preventsDefault = preventsDefault
    self.action = action
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // A key handler needs a focus destination even when its view is a layout
    // container. Without a tab stop, handlers only run while a descendant
    // control happens to hold focus and keyboard shortcuts are unavailable on
    // canvases and other non-control surfaces.
    var focusTargetAvailable = false
    Self.apply(name: name, preventsDefault: preventsDefault, action: action, to: node, context: &context, focusTargetAvailable: &focusTargetAvailable)
  }

  @MainActor private static func apply(
    name: String,
    preventsDefault: Bool,
    action: @escaping (SwiftUIWebKeyEvent) -> Void,
    to node: _RenderNode,
    context: inout _RenderContext,
    focusTargetAvailable: inout Bool
  ) {
    // Layout containers may lower to fragments without a DOM host. Put the
    // event on their rendered descendants so bubbling keyboard events still
    // find the nearest Swift handler after fragment flattening.
    if case .fragment = node.kind {
      for child in node.children {
        apply(name: name, preventsDefault: preventsDefault, action: action, to: child, context: &context, focusTargetAvailable: &focusTargetAvailable)
      }
      return
    }

    node.events[name] = _EventHandler(name: name, action: { raw in action(SwiftUIWebKeyEvent(payload: raw)) }, preventsDefault: preventsDefault)
    guard !focusTargetAvailable else { return }
    let nativeFocusTarget: Bool
    if case .element(let tag) = node.kind {
      nativeFocusTarget = ["a", "button", "input", "select", "summary", "textarea"].contains(tag)
    } else {
      nativeFocusTarget = false
    }
    if nativeFocusTarget || node.attributes["tabindex"] != nil {
      focusTargetAvailable = true
    } else {
      node.attributes["tabindex"] = "0"
      focusTargetAvailable = true
    }
  }
}
