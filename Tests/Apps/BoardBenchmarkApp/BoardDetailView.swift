import SwiftUIWeb

/// The work that was opened, or a hint to open one.
struct BoardDetailView: View {
  let work: BoardWork?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let work {
        Text(work.title).font(.title3).fontWeight(.bold).accessibilityIdentifier("detail-title")
        Text(work.status)
      } else {
        Text("Select a work")
      }
    }
  }
}
