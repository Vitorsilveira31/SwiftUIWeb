import SwiftUIWeb

/// The pages for a header too narrow for the row of pills: a button with the icon only, so it never competes with the brand for
/// room, that opens the list of pages under the header (`SiteCompactNavList`). A `Menu` would not do: its items are buttons, and
/// a page is a link.
struct SiteCompactNavMenu: View {
  @Binding var isOpen: Bool
  @Environment(\.siteLanguage) private var language

  var body: some View {
    Button { isOpen.toggle() } label: {
      Label(ShellStrings.menuLabel(language), systemImage: isOpen ? "xmark.circle" : "line.3.horizontal").labelStyle(.iconOnly)
    }
    .buttonStyle(.bordered)
    .accessibilityLabel(ShellStrings.menuLabel(language))
  }
}
