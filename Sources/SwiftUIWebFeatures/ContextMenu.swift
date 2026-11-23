@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// SwiftUI's `contextMenu(menuItems:)`.
///
/// The menu items are ordinary Swift views (buttons, dividers, labels) kept
/// in the retained tree inside a hidden `role="menu"` panel. The browser host
/// opens the panel at the pointer on a secondary click, the keyboard context
/// menu key, or a touch long-press, and dismisses it after an item is chosen,
/// on Escape, or on an outside click — the iPad/iPhone interaction model.
/// The optional `preview` of iOS has no browser equivalent and is not shown.
public extension View {
  nonisolated func contextMenu<MenuItems: View>(@ViewBuilder menuItems: () -> MenuItems) -> some View {
    _modified(ContextMenuModifier(items: menuItems()))
  }

  nonisolated func contextMenu<MenuItems: View, Preview: View>(@ViewBuilder menuItems: () -> MenuItems, @ViewBuilder preview: () -> Preview) -> some View {
    _modified(ContextMenuModifier(items: menuItems()))
  }
}

package nonisolated struct ContextMenuModifier<MenuItems: View>: ViewModifier {
  let items: MenuItems

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    let rendered = items._render(in: context.child(_FiberKey("context-menu")))
    // A menu without items (e.g. an empty conditional) behaves like SwiftUI:
    // no context menu at all.
    let isEmpty = rendered.isEmpty || (rendered.kind == .fragment && rendered.children.allSatisfy { $0.isEmpty })
    // Keep the wrapper even when empty so the content's identity is stable.
    _semanticWrap(node, kind: "zstack")
    node.classes.append("context-menu-host")
    guard !isEmpty else { return }
    node.attributes["data-context-menu"] = "true"
    let panel = _RenderNode.element("div")
    panel.classes = ["context-menu-panel"]
    panel.attributes["role"] = "menu"
    panel.attributes["popover"] = "manual"
    panel.attributes["tabindex"] = "-1"
    panel.children = rendered.kind == .fragment ? rendered.children : [rendered]
    node.children.append(panel)
  }
}
