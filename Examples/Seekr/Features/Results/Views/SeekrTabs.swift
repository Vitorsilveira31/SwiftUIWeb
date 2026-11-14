import SwiftUIWeb

/// All, Images and News: the open tab has a bar under its name.
struct SeekrTabs: View {
  let results: SeekrResultsViewModel

  var body: some View {
    HStack(alignment: .top, spacing: 22) {
      ForEach(SeekrTab.allCases, id: \.self) { tab in
        Button { Task { await results.select(tab) } } label: {
          VStack(spacing: 6) {
            Text(ResultsStrings.title(tab))
              .foregroundStyle(tab == results.tab ? SeekrPalette.indigo : .secondary)
            Rectangle()
              .fill(tab == results.tab ? SeekrPalette.indigo : Color.clear)
              .frame(height: 3)
          }
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
  }
}
