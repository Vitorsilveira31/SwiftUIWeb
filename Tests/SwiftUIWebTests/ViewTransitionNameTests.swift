import Foundation
import Testing
import SwiftUIWeb

/// The view-transition names of matched views (`ApplePlatformParity.swift`): the source names its element, and only the source.
@Suite
@MainActor
struct ViewTransitionNameTests {
  private struct Pair: View {
    @Namespace private var namespace
    var body: some View {
      VStack {
        Text("Source").matchedGeometryEffect(id: "card", in: namespace)
        Text("Shadow").matchedGeometryEffect(id: "card", in: namespace, isSource: false)
        Text("Origin").matchedTransitionSource(id: "origin", in: namespace)
      }
    }
  }

  @Test
  func theSourceNamesItsElementAndTheNonSourceDoesNot() {
    let html = StaticHTMLFiberRenderer().render(Pair())
    let names = html.components(separatedBy: "view-transition-name: vt-").count - 1
    #expect(names == 2, "one name for the matched source and one for the transition source, got \(names)")
    #expect(html.contains("Shadow"))
  }

  @Test
  func aNamedElementCarriesItsNameInTheStyleAttribute() {
    let html = StaticHTMLFiberRenderer().render(Pair())
    #expect(html.contains("view-transition-name: vt-"))
  }
}
