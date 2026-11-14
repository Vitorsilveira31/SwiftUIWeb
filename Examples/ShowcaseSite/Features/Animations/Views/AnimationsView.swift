import SwiftUIWeb

/// Motion: the animation API of SwiftUI, each piece running live.
struct AnimationsView: View {
  @Environment(\.siteLanguage) private var language

  var body: some View {
    SitePageScaffold(width: SiteLayout.wideWidth) {
      SiteHeading(text: AnimationsStrings.title(language), isPageTitle: true)
      SiteParagraph(text: AnimationsStrings.lead(language), isLead: true)
      AdaptiveColumnsLayout(minimumWidth: 322, spacing: 14, rowHeight: AnimationDemoCard<EmptyView>.height) {
        ForEach(AnimationsStrings.all(language), id: \.id) { demo in
          AnimationDemoCard(demo: demo, codeLabel: AnimationsStrings.codeLabel(language), doneLabel: AnimationsStrings.doneLabel(language)) {
            demoView(demo.id)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func demoView(_ id: String) -> some View {
    switch id {
    case "numeric-text": NumericTextDemo()
    case "transitions": TransitionsDemo()
    case "curves": CurvesDemo()
    case "matched-geometry": MatchedGeometryDemo()
    case "phase": PhaseDemo()
    case "keyframes": KeyframeDemo()
    case "symbol-effects": SymbolEffectDemo()
    case "progress-ring": ProgressRingDemo()
    default: EmptyView()
    }
  }
}
