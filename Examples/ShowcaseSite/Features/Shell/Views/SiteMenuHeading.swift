import SwiftUIWeb

/// The small heading of a group of items in a menu.
struct SiteMenuHeading: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12)
      .padding(.top, 6)
  }
}
