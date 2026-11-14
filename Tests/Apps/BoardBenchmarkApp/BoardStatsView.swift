import SwiftUIWeb

/// The stats screen: a 20 by 10 grid of numbers that depend on how many works there are.
struct BoardStatsView: View {
  let workCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Stats").font(.title3).fontWeight(.bold).accessibilityIdentifier("stats-title")
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
        ForEach(0..<200, id: \.self) { index in
          Text("\(BoardData.statsCell(row: index / 10, column: index % 10, workCount: workCount))")
            .padding(8)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("stats-cell")
        }
      }
      .accessibilityIdentifier("stats-grid")
    }
  }
}
