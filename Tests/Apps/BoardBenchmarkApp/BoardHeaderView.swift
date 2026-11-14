import SwiftUIWeb

/// The title and the buttons that switch between the board and the stats.
struct BoardHeaderView: View {
  let model: BoardModel

  var body: some View {
    HStack(spacing: 8) {
      Text("Works board").font(.title3).fontWeight(.bold)
      Spacer()
      Button("Board") { model.screen = .board }.accessibilityIdentifier("view-board")
      Button("Stats") { model.screen = .stats }.accessibilityIdentifier("view-stats")
    }
    .frame(height: 56)
  }
}
