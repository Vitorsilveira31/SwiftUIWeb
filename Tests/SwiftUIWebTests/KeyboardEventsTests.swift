import Testing
@testable import SwiftUIWeb
import SwiftUIWebCore
import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
struct KeyboardEventsTests {
  @Test
  func keyHandlersPropagateAcrossFlattenedFragmentsWithOneTabStop() {
    struct FragmentWithKeys: View {
      let action: @MainActor (SwiftUIWebKeyEvent) -> Void
      var body: some View {
        Group {
          Text("first")
          Text("second")
        }
        .onKeyDown(perform: action)
      }
    }
    func collect(_ node: _RenderNode, into hosts: inout [_RenderNode]) {
      if node.events["keyDown"] != nil { hosts.append(node) }
      for child in node.children { collect(child, into: &hosts) }
    }

    var received: SwiftUIWebKeyEvent?
    let tree = FiberTree(FragmentWithKeys { received = $0 })
    var hosts: [_RenderNode] = []
    collect(tree.renderNode, into: &hosts)
    #expect(hosts.count == 2)
    #expect(hosts[0].attributes["tabindex"] == "0")
    #expect(hosts[1].attributes["tabindex"] == nil)

    tree.dispatch(event: "keyDown", value: "KeyZ,0,0,1,0,0,0", on: hosts[1])
    #expect(received?.code == "KeyZ")
    #expect(received?.command == true)
  }

  @Test
  func keyHandlersRenderAndDecodeBrowserModifiers() {
    var down: SwiftUIWebKeyEvent?
    var up: SwiftUIWebKeyEvent?
    let tree = FiberTree(Text("Workflow canvas")
      .onKeyDown(preventsDefault: true) { down = $0 }
      .onKeyUp { up = $0 })

    tree.dispatch(event: "keyDown", value: "KeyZ,1,1,1,0,0,1")
    tree.dispatch(event: "keyUp", value: "Space,0,0,0,0,0,0")

    #expect(down?.code == "KeyZ")
    #expect(down?.shift == true)
    #expect(down?.control == true)
    #expect(down?.command == true)
    #expect(down?.isEditable == true)
    #expect(up?.code == "Space")
    #expect(tree.renderNode.events["keyDown"]?.preventsDefault == true)
    #expect(tree.renderNode.htmlDescription.contains("data-fiber-event-keyDown"))
    #expect(tree.renderNode.attributes["tabindex"] == "0")
  }

  @Test
  func keyEventValuesPreserveAllFlagsAndMalformedPayloadsDefaultSafely() {
    let explicit = SwiftUIWebKeyEvent(
      code: "Tab", shift: true, control: true, command: true, option: true,
      isRepeat: true, isEditable: true
    )
    #expect(explicit.code == "Tab")
    #expect(explicit.shift && explicit.control && explicit.command)
    #expect(explicit.option && explicit.isRepeat && explicit.isEditable)

    var received: SwiftUIWebKeyEvent?
    let tree = FiberTree(Text("Keyboard target").onKeyDown { received = $0 })
    tree.dispatch(event: "keyDown", value: "Escape")
    #expect(received?.code == "Escape")
    #expect(received?.shift == false)
    #expect(received?.control == false)
    #expect(received?.command == false)
    #expect(received?.option == false)
    #expect(received?.isRepeat == false)
    #expect(received?.isEditable == false)

    tree.dispatch(event: "keyDown", value: "")
    #expect(received?.code == "")
    #expect(received?.shift == false)
  }
}
