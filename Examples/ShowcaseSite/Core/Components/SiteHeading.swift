import SwiftUIWeb

/// A page or section title.
struct SiteHeading: View {
  let text: String
  var isPageTitle = false

  var body: some View {
    Text(text)
      .font(isPageTitle ? .largeTitle : .title2)
      .fontWeight(.bold)
      .accessibilityAddTraits(.isHeader)
  }
}
