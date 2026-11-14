/// Browser chrome emitted by `TabView` with `.tabViewStyle(.sidebarAdaptable)`.
///
/// The Swift side emits one semantic sidebar surface; the browser host picks
/// its presentation from the viewport width and sets `data-tab-layout` on the
/// tab view (`sidebar`, `rail` or `mobile`):
///
///     div.tab-view
///       div.tab-body              (panels, laid out by CSS)
///       div.tab-mobile-backdrop      (mobile overlay)
///       div.tab-sidebar              (sidebar / rail / mobile panel)
///         div.tab-sidebar-header     (tabViewSidebarHeader + toggle)
///         div.tab-list[role=tablist] (tabs and section titles)
///         div.tab-sidebar-footer-content      (tabViewSidebarFooter)
///         div.tab-sidebar-bottom-bar-content  (tabViewSidebarBottomBar)
///       button.tab-mobile-toggle     (mobile floating button)
///
/// Colors and geometry come from `--tab-*` custom properties so an
/// application stylesheet can restyle the shell without Swift changes.
func _adaptiveTabChrome(tabBar: _RenderNode, sidebarID: String, badges: [String]) -> [_RenderNode] {
  let backdrop = _RenderNode.element("div")
  backdrop.key = _FiberKey("__tab_mobile_backdrop")
  backdrop.classes = ["tab-mobile-backdrop"]
  backdrop.attributes["data-tab-mobile-backdrop"] = "true"
  backdrop.attributes["aria-hidden"] = "true"
  backdrop.attributes["hidden"] = "hidden"

  let header = _RenderNode.element("div")
  header.key = _FiberKey("__tab_sidebar_header")
  header.classes = ["tab-sidebar-header"]
  header.attributes["data-tab-sidebar-header"] = "true"

  let toggle = _RenderNode.element("button")
  toggle.key = _FiberKey("__tab_sidebar_toggle")
  toggle.attributes["type"] = "button"
  toggle.classes = ["tab-sidebar-toggle"]
  toggle.attributes["data-tab-sidebar-toggle"] = "true"
  toggle.attributes["aria-controls"] = sidebarID
  toggle.attributes["aria-label"] = "Expand navigation"
  toggle.attributes["aria-expanded"] = "false"
  toggle.children = [_tabChromeSymbol("sidebar.left", className: "tab-sidebar-toggle-icon")]
  header.children = [toggle]

  let sidebar = _RenderNode.element("div")
  sidebar.key = _FiberKey("__tab_sidebar")
  sidebar.classes = ["tab-sidebar"]
  sidebar.attributes["id"] = sidebarID
  sidebar.attributes["data-tab-sidebar"] = "true"
  sidebar.children = [header, tabBar]

  let fab = _RenderNode.element("button")
  fab.key = _FiberKey("__tab_mobile_toggle")
  fab.classes = ["tab-mobile-toggle"]
  fab.attributes["type"] = "button"
  fab.attributes["data-tab-mobile-toggle"] = "true"
  fab.attributes["aria-controls"] = sidebarID
  fab.attributes["aria-label"] = "Open app navigation"
  fab.attributes["aria-expanded"] = "false"
  fab.children = [
    _tabChromeSymbol("line.3.horizontal", className: "tab-mobile-open-icon"),
    _tabChromeSymbol("xmark", className: "tab-mobile-close-icon")
  ]
  // The floating button summarizes numeric tab badges while the menu is
  // closed, like the badge on a collapsed app switcher.
  // Saturating: badge counts can come from a server, and Int is 32 bits in the browser build.
  let total = badges.reduce(0) { sum, badge in
    let (next, overflow) = sum.addingReportingOverflow(max(0, Int(badge) ?? 0))
    return overflow ? Int.max : next
  }
  if total > 0 {
    let badge = _RenderNode.element("span")
    badge.classes = ["tab-badge", "tab-mobile-badge"]
    badge.attributes["aria-hidden"] = "true"
    badge.children = [.text(String(total))]
    fab.children.append(badge)
    fab.attributes["data-badge"] = String(total)
  }
  return [backdrop, sidebar, fab]
}

/// A tab badge. `.badge("•")` is the documented activity convention: it
/// renders a pulsing dot instead of a count and is hidden from assistive
/// technology (the host adds the localized activity phrase to the tab's
/// accessible name instead).
func _tabBadgeNode(_ badge: String) -> _RenderNode {
  let node = _RenderNode.element("span")
  node.classes = ["tab-badge"]
  if _isTabActivityBadge(badge) {
    node.attributes["data-badge-style"] = "dot"
    node.attributes["aria-hidden"] = "true"
  } else {
    node.attributes["aria-label"] = badge
    node.children = [.text(badge)]
  }
  return node
}

func _isTabActivityBadge(_ badge: String) -> Bool {
  badge == "\u{2022}" || badge == "\u{25CF}"
}

private func _tabChromeSymbol(_ symbol: String, className: String) -> _RenderNode {
  let icon = _RenderNode.element("span")
  icon.classes = [className, "symbol-icon"]
  icon.attributes["data-symbol"] = symbol
  icon.attributes["aria-hidden"] = "true"
  return icon
}

/// Whether a view on screen inside `root` asks for the tab bar to be hidden: `toolbar(.hidden, for: .tabBar)`.
/// Views a NavigationStack keeps behind its top screen and the panels of unselected tabs are not on screen, so they
/// do not count. The walk is iterative, like the navigation toolbar extraction, so deep screens do not use the stack.
/// Whether a view has asked for `toolbar(.hidden, for: .tabBar)` since the app started (set when the modifier is made).
/// Only ever set to true, so a read that races the write at worst walks the tab once more.
enum _TabBarHiding {
  nonisolated(unsafe) static var requested = false
}

func _requestsHiddenTabBar(_ root: _RenderNode) -> Bool {
  // Most apps never hide the tab bar: until a view asks to, there is nothing to look for in the selected tab.
  guard _TabBarHiding.requested else { return false }
  var pending = [root]
  while let node = pending.popLast() {
    if node.attributes[_toolbarVisibilityAttribute(.tabBar)] == "hidden" {
      return true
    }
    for child in node.children
    where child.attributes["data-navigation-inactive"] != "true" && child.attributes["data-tab-hidden"] != "true" {
      pending.append(child)
    }
  }
  return false
}
