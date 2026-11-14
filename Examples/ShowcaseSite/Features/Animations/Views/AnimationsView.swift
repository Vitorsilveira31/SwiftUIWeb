import SwiftUIWeb

/// Motion: the animation API of SwiftUI, each piece running live.
struct AnimationsView: View {
  @Environment(\.siteLanguage) private var language

  private static let spacing: CGFloat = 14
  private static let cardWidth: CGFloat = 322

  var body: some View {
    SitePageScaffold(width: SiteLayout.wideWidth) {
      SiteHeading(text: AnimationsStrings.title(language), isPageTitle: true)
      SiteParagraph(text: AnimationsStrings.lead(language), isLead: true)
      // The cards hold their own state (a counter, a toggle), so they are laid out in plain stacks, not in a lazy grid, and
      // the widest arrangement that fits the page is the one shown.
      ViewThatFits(in: .horizontal) {
        grid(columns: 3)
        grid(columns: 2)
        grid(columns: 1)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private func grid(columns: Int) -> some View {
    let demos = AnimationsStrings.all(language)
    let rows = Array(stride(from: 0, to: demos.count, by: columns)).map { start in
      Array(demos[start..<min(start + columns, demos.count)])
    }
    return VStack(spacing: Self.spacing) {
      ForEach(rows.indices, id: \.self) { row in
        HStack(alignment: .top, spacing: Self.spacing) {
          ForEach(rows[row], id: \.id) { demo in card(demo) }
          // A short last row keeps the width of the others.
          ForEach(0..<(columns - rows[row].count), id: \.self) { _ in
            Color.clear.frame(width: Self.cardWidth, height: 0)
          }
        }
      }
    }
  }

  private func card(_ demo: AnimationDemoVO) -> some View {
    AnimationDemoCard(demo: demo, codeLabel: AnimationsStrings.codeLabel(language), doneLabel: AnimationsStrings.doneLabel(language)) {
      demoView(demo.id)
    }
    .frame(width: Self.cardWidth)
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
