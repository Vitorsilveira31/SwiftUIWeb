import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A `ViewModifier` that reads `@Environment` only inside an event handler
/// (never during `body(content:)`) still resolves the objects and values its
/// parent supplied when the handler runs after the render pass, on every
/// host, exactly like a view's action closure.
@Suite
@MainActor
struct EnvironmentModifierHandlerTests {
  @Observable final class Router {
    var dialog: String?
  }

  struct Shortcuts: ViewModifier {
    @Environment(Router.self) private var router
    @Environment(\.isEnabled) private var isEnabled
    let seen: (String, Bool) -> Void

    func body(content: Content) -> some View {
      content.onKeyDown { event in handle(event) }
    }

    private func handle(_ event: SwiftUIWebKeyEvent) {
      if event.code == "Escape" { router.dialog = nil } else { router.dialog = event.code }
      seen(event.code, isEnabled)
    }
  }

  @Test
  func modifierHandlersReadTheEnvironmentTheirParentSupplies() {
    let router = Router()
    var seen: [(String, Bool)] = []
    let tree = FiberTree(
      Text("shell")
        .modifier(Shortcuts { seen.append(($0, $1)) })
        .environment(router)
        .disabled(true)
    )
    tree.dispatch(event: "keyDown", value: "KeyK,0,0,1,0,0,0")
    #expect(router.dialog == "KeyK")
    tree.dispatch(event: "keyDown", value: "Escape,0,0,0,0,0,0")
    #expect(router.dialog == nil)
    #expect(seen.map(\.0) == ["KeyK", "Escape"])
    #expect(seen.map(\.1) == [false, false], "the keyPath form resolves the wrapping environment too")
  }

  @Test
  func modifierHandlersKeepResolvingAfterTheTreeUpdates() {
    let router = Router()
    let tree = FiberTree(Text("shell").modifier(Shortcuts { _, _ in }).environment(router))
    router.dialog = "palette"
    _ = tree.update(Text("shell").modifier(Shortcuts { _, _ in }).environment(router))
    tree.dispatch(event: "keyDown", value: "Escape,0,0,0,0,0,0")
    #expect(router.dialog == nil)
  }
}
