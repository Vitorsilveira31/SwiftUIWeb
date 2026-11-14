import SwiftUIWeb

/// The board: a header with the two screens, then the screen shown.
struct BoardRootView: View {
  @State private var model = BoardModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      BoardHeaderView(model: model)
      if model.screen == .stats {
        BoardStatsView(workCount: model.works.count)
      } else {
        BoardScreenView(model: model)
      }
    }
    .padding(.horizontal, 20)
    .frame(maxWidth: 1100)
  }
}
