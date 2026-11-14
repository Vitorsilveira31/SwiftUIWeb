import SwiftUIWeb

/// The works that match the search, in a lazy list: only the rows in view are built.
struct BoardListView: View {
  let model: BoardModel
  let works: [BoardWork]

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(works) { work in
          BoardRowView(
            work: work,
            isFavorite: model.favorites.contains(work.id),
            isSelected: work.id == model.selectedID,
            model: model
          )
        }
      }
    }
    .frame(height: 600)
    .accessibilityIdentifier("list")
  }
}
