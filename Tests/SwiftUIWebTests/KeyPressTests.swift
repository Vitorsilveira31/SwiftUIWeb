import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite(.serialized)
@MainActor
struct KeyPressTests {
  private func first(_ node: _RenderNode, _ predicate: (_RenderNode) -> Bool) -> _RenderNode? {
    if predicate(node) { return node }
    for child in node.children { if let found = first(child, predicate) { return found } }
    return nil
  }

  /// Mirrors the browser host: returns whether Swift reported `.handled`.
  private func press(_ tree: FiberTree, _ payload: String, on node: _RenderNode?) -> Bool {
    _ = _KeyPressDispatch._consumeHandled()
    tree.dispatch(event: "keyPress", value: payload, on: node)
    return _KeyPressDispatch._consumeHandled()
  }

  @Test
  func payloadDecodesPhaseKeyCharactersAndModifiers() {
    let press = KeyPress(_webPayload: "down\tArrowUp\t18")
    #expect(press?.phase == .down)
    #expect(press?.key == .upArrow)
    #expect(press?.modifiers == [.shift, .command])
    #expect(KeyPress(_webPayload: "repeat\ta\t0")?.characters == "a")
    #expect(KeyPress(_webPayload: "up\tEnter\t0")?.characters == "\r")
    #expect(KeyPress(_webPayload: "down\tShift\t2") == nil)
    #expect(KeyPress(_webPayload: "sideways\ta\t0") == nil)
  }

  @Test
  func keyFilterPhasesAndResultAreHonored() {
    var log: [String] = []
    let tree = FiberTree(Text("List")
      .focusable()
      .onKeyPress(.downArrow) { log.append("down"); return .handled }
      .onKeyPress(.upArrow, phases: .up) { press in log.append("up-\(press.phase == .up)"); return .ignored })
    let host = tree.findNode(withEvent: "keyPress")
    #expect(host?.attributes["tabindex"] == "0")

    #expect(press(tree, "down\tArrowDown\t0", on: host))
    #expect(press(tree, "repeat\tArrowDown\t0", on: host))
    #expect(!press(tree, "up\tArrowDown\t0", on: host))
    #expect(!press(tree, "down\tArrowUp\t0", on: host))
    #expect(!press(tree, "up\tArrowUp\t0", on: host))
    #expect(log == ["down", "down", "up-true"])
  }

  @Test
  func innerHandlerRunsFirstAndHandledStopsOuterHandlersOnTheSameElement() {
    var log: [String] = []
    let tree = FiberTree(Text("Field")
      .onKeyPress(keys: [.escape, .return]) { press in log.append("inner"); return press.key == .escape ? .handled : .ignored }
      .onKeyPress(phases: .all) { _ in log.append("outer"); return .handled })
    let host = tree.findNode(withEvent: "keyPress")
    #expect(press(tree, "down\tEscape\t0", on: host))
    #expect(log == ["inner"])
    #expect(press(tree, "down\tEnter\t0", on: host))
    #expect(log == ["inner", "inner", "outer"])
  }

  @Test
  func ancestorsReceiveIgnoredPressesAsSeparateDispatchTargets() {
    var log: [String] = []
    let tree = FiberTree(VStack {
      TextField("Search", text: .constant(""))
        .onKeyPress(.downArrow) { log.append("field"); return .ignored }
    }
    .onKeyPress(.downArrow) { log.append("container"); return .handled })
    let field = first(tree.renderNode) { $0.attributes["data-control-kind"] == "text-field" }
    let container = first(tree.renderNode) { $0.events["keyPress"] != nil && $0 !== field }
    // The host walks outward after an ignored result.
    #expect(!press(tree, "down\tArrowDown\t0", on: field))
    #expect(press(tree, "down\tArrowDown\t0", on: container))
    #expect(log == ["field", "container"])
  }

  @Test
  func payloadNamesTheEnclosingHandlersAfterThePress() {
    let split = _KeyPressDispatch._splitEnclosingHandlers("down\tx\t18\t30,12")
    #expect(split.press == "down\tx\t18")
    #expect(split.enclosing == [30, 12])
    let alone = _KeyPressDispatch._splitEnclosingHandlers("up\tEscape\t0")
    #expect(alone.press == "up\tEscape\t0")
    #expect(alone.enclosing.isEmpty)
    // The press decodes the same with or without the ids after it.
    #expect(KeyPress(_webPayload: "down\tArrowUp\t18\t30")?.modifiers == [.shift, .command])
  }

  /// The host sends one call for the whole walk (`FiberTree.dispatchKeyPress`): each handler, innermost first, until one
  /// returns `.handled`.
  @Test
  func oneDispatchWalksTheEnclosingHandlersUntilOneHandlesThePress() {
    var log: [String] = []
    let tree = FiberTree(VStack {
      TextField("Search", text: .constant(""))
        .onKeyPress(keys: [.downArrow, .escape]) { press in log.append("field"); return press.key == .escape ? .handled : .ignored }
    }
    .onKeyPress(.downArrow) { log.append("container"); return .handled })
    guard let field = first(tree.renderNode, { $0.attributes["data-control-kind"] == "text-field" }),
          let container = first(tree.renderNode, { $0.events["keyPress"] != nil && $0 !== field }) else {
      Issue.record("key press hosts not rendered"); return
    }
    #expect(tree.dispatchKeyPress("down\tArrowDown\t0", on: field, enclosing: [container]))
    #expect(log == ["field", "container"])
    #expect(tree.dispatchKeyPress("down\tEscape\t0", on: field, enclosing: [container]))
    #expect(log == ["field", "container", "field"], "a handled press never reaches the enclosing handler")
    #expect(!tree.dispatchKeyPress("down\tq\t0", on: field, enclosing: [container]))
    #expect(log == ["field", "container", "field"])
  }

  private struct Counter: View {
    @State private var presses = 0
    var body: some View {
      Text("presses:\(presses)")
        .focusable()
        .onKeyPress(.return) { presses += 1; return .handled }
    }
  }

  /// The Embedded host publishes after a key press only when it left something to render.
  @Test
  func anIgnoredPressLeavesNothingToRenderAndAStateWriteDoes() {
    let tree = FiberTree(Counter())
    _ = tree.renderNode
    guard let host = tree.findNode(withEvent: "keyPress") else { Issue.record("no key press host"); return }
    #expect(!tree.dispatchKeyPress("down\tx\t0", on: host, enclosing: []))
    #expect(!tree._hasPendingInvalidation)
    #expect(tree.dispatchKeyPress("down\tEnter\t0", on: host, enclosing: []))
    #expect(tree._hasPendingInvalidation)
    #expect(tree.renderNode.htmlDescription.contains("presses:1"))
    #expect(!tree._hasPendingInvalidation)
  }

  @Test
  func charactersOverloadFiltersByCharacterSet() {
    var typed = ""
    let tree = FiberTree(Text("Grid").onKeyPress(characters: .decimalDigits) { press in typed += press.characters; return .handled })
    let host = tree.findNode(withEvent: "keyPress")
    #expect(press(tree, "down\t7\t0", on: host))
    #expect(!press(tree, "down\tq\t0", on: host))
    #expect(!press(tree, "down\tArrowUp\t0", on: host))
    #expect(typed == "7")
  }

  @Test
  func disabledViewsDoNotInstallKeyHandlers() {
    let tree = FiberTree(Text("Off").onKeyPress(.space) { .handled }.disabled(true))
    #expect(tree.findNode(withEvent: "keyPress") == nil)
  }
}
