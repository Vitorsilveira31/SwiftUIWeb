import SwiftUIWeb

/// The component catalog: the list beside the entry on a wide screen, a menu above it on a narrow one. The width the page has
/// decides, not what the entry draws, so a wide preview never pushes the entry below the list.
///
/// Nothing is drawn until the width has been measured once, so a phone never shows the wide layout for a moment and a desktop
/// never shows the narrow one. (`ViewThatFits` would avoid that too, but it keeps both candidates in the page, and the entry's
/// live component would exist twice.)
struct ComponentsView: View {
  let viewModel: ComponentsViewModel
  @State private var isWide: Bool?

  var body: some View {
    Group {
      switch isWide {
      case .some(true): ComponentsWideLayout(viewModel: viewModel)
      case .some(false): ComponentsNarrowLayout(viewModel: viewModel)
      case .none: Color.clear
      }
    }
    .onGeometryChange(for: Bool.self, of: { $0.size.width >= SiteLayout.splitWidth }) { isWide = $0 }
  }
}
