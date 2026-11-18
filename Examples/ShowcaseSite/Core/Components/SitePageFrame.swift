import SwiftUIWeb

/// The content column of the site: the screen's width less a margin on each side, never wider than
/// `SiteLayout.contentWidth`, and centered. The header and every page sit in it, so their left edges line up whatever the
/// page and whatever the screen.
struct SitePageFrame<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .frame(maxWidth: SiteLayout.contentWidth)
      .padding(.horizontal, SiteLayout.gutter)
      .frame(maxWidth: .infinity)
  }
}
