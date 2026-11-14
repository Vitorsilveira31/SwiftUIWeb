import SwiftUIWeb
#if canImport(SwiftUIWebWeb)
import SwiftUIWebWeb
#endif

/// What a page tells the browser: its address, its title and its description. On Apple platforms there is no address or head
/// to set, so the page is left as it is.
struct SitePageMetadata: ViewModifier {
  let route: SiteRoute
  let entryName: String?
  let language: SiteLanguage

  func body(content: Content) -> some View {
    #if canImport(SwiftUIWebWeb)
    content
      .path(route.segments)
      .navigationTitle(ShellStrings.documentTitle(page: route.page, entry: entryName, language))
      .documentHead { .meta(name: "description", content: ShellStrings.description(language)) }
    #else
    content
    #endif
  }
}
