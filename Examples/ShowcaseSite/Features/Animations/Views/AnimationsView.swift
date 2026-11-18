import SwiftUIWeb

/// Motion: the animation API of SwiftUI, each piece running live.
struct AnimationsView: View {
  @Environment(\.siteLanguage) private var language
  /// The animation whose code is open over the page, if any.
  @State private var codeDemo: AnimationDemoVO?

  var body: some View {
    SitePageScaffold {
      SitePageHeader(title: AnimationsStrings.title(language), lead: AnimationsStrings.lead(language))
      AdaptiveColumnsLayout(minimumWidth: SiteLayout.demoCardMinWidth, spacing: SiteLayout.gridSpacing, rowHeight: AnimationDemoCard<EmptyView>.height) {
        ForEach(AnimationsStrings.all(language), id: \.id) { demo in
          AnimationDemoCard(demo: demo, codeLabel: AnimationsStrings.codeLabel(language), shownCode: $codeDemo) {
            demoView(demo.id)
          }
        }
      }
    }
    // One sheet for the page, over every card: opened from a card, it would sit in that card's stacking order.
    .sheet(item: $codeDemo) { demo in
      AnimationCodeSheet(demo: demo, doneLabel: AnimationsStrings.doneLabel(language), shown: $codeDemo)
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
