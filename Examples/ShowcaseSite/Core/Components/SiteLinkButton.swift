import SwiftUIWeb

/// A link that looks like a button: a real `<a href>` to another page of the site, so it opens in a new tab and Back returns to
/// the page before. The browser host shows the page through `onOpenURL` instead of reloading.
struct SiteLinkButton: View {
  let title: String
  let destination: URL
  var isProminent = false

  var body: some View {
    Link(destination: destination) {
      Text(title)
        // One line, at its own width: a button squeezed by its row would wrap its label and grow a second line.
        .lineLimit(1)
        .fixedSize()
        .fontWeight(.semibold)
        .foregroundStyle(isProminent ? Color.white : Color.primary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(isProminent ? SiteTheme.accent : Color.primary.opacity(0.08))
        .clipShape(Capsule())
    }
  }
}
