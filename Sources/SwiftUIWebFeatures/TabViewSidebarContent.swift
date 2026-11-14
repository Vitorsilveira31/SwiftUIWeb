@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// SwiftUI sidebar customization points. Content is rendered through Fiber so
/// buttons and state retain the same identity as the surrounding tab view.
///
/// With `.tabViewStyle(.sidebarAdaptable)` the browser host places them as:
/// - header: the sidebar's top row, before the collapse toggle. When the
///   sidebar collapses to a rail the header content hides and the toggle
///   shows the first `Image` found in the header (the app logo), swapping to
///   the sidebar icon on hover/focus.
/// - footer: shown only in the mobile navigation panel, after the tabs. Set
///   `--tab-sidebar-footer-display: block` to also show it in the
///   sidebar.
/// - bottom bar: pinned below the tabs with a top border. A collapsed rail
///   keeps only its first element (for example an avatar), centered.
extension View {
  public nonisolated func tabViewSidebarHeader<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    modifier(_TabViewSidebarContentModifier(placement: "header", content: content()))
  }

  public nonisolated func tabViewSidebarFooter<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    modifier(_TabViewSidebarContentModifier(placement: "footer", content: content()))
  }

  public nonisolated func tabViewSidebarBottomBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    modifier(_TabViewSidebarContentModifier(placement: "bottom-bar", content: content()))
  }
}

nonisolated struct _TabViewSidebarContentModifier<Content: View>: ViewModifier {
  let placement: String
  let content: Content

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard let tabView = findTabView(node) else { return }
    let wrapper = _RenderNode.element("div")
    wrapper.key = _FiberKey("__tab_sidebar_\(placement)")
    wrapper.classes = ["tab-sidebar-\(placement)-content"]
    wrapper.attributes["data-tab-sidebar-content"] = placement
    // Enter the renderer boundary so each placement gets its own StateScope and retained observation owner.
    let rendered = AnyView(content)._render(in: context.child(_FiberKey("__tab_sidebar_\(placement)")))
    if !rendered.isEmpty { wrapper.children = [rendered] }
    let sidebar = tabView.children.first { $0.attributes["data-tab-sidebar"] == "true" }
    switch placement {
    case "header":
      guard let header = sidebar?.children.first(where: { $0.attributes["data-tab-sidebar-header"] == "true" })
      else { return }
      header.children.insert(wrapper, at: 0)
      if let toggle = header.children.first(where: { $0.attributes["data-tab-sidebar-toggle"] == "true" }),
         let logo = _sidebarLogo(in: rendered) {
        toggle.children.insert(logo, at: 0)
        toggle.attributes["data-tab-has-logo"] = "true"
      }
    case "footer":
      if let sidebar {
        let bottomBar = sidebar.children.firstIndex { $0.attributes["data-tab-sidebar-content"] == "bottom-bar" }
        sidebar.children.insert(wrapper, at: bottomBar ?? sidebar.children.count)
        tabView.attributes["data-tab-has-footer"] = "true"
      } else {
        // The automatic style docks its tab list in a `.tab-bar` row.
        let dock = tabView.children.first { $0.classes.contains("tab-bar") }
        (dock?.children ?? tabView.children).first(where: { $0.classes.contains("tab-list") })?
          .children.append(wrapper)
      }
    default:
      if let sidebar { sidebar.children.append(wrapper) } else { tabView.children.append(wrapper) }
      tabView.attributes["data-tab-has-bottom-bar"] = "true"
    }
  }

  @MainActor private func findTabView(_ node: _RenderNode) -> _RenderNode? {
    if node.classes.contains("tab-view") { return node }
    for child in node.children {
      if let result = findTabView(child) { return result }
    }
    return nil
  }

  /// The collapsed rail's toggle shows the app logo: a presentation-only copy
  /// of the first image in the header content.
  @MainActor private func _sidebarLogo(in node: _RenderNode) -> _RenderNode? {
    guard let image = _firstImage(in: node) else { return nil }
    let logo = _RenderNode.element("img")
    logo.key = _FiberKey("__tab_sidebar_toggle_logo")
    logo.classes = ["tab-sidebar-toggle-logo"]
    logo.attributes["src"] = image.attributes["src"]
    logo.attributes["alt"] = ""
    logo.attributes["aria-hidden"] = "true"
    logo.attributes["decoding"] = "async"
    return logo
  }

  @MainActor private func _firstImage(in node: _RenderNode) -> _RenderNode? {
    if node.kind == .element("img"), node.attributes["src"] != nil { return node }
    for child in node.children {
      if let image = _firstImage(in: child) { return image }
    }
    return nil
  }
}
