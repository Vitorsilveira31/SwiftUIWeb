import SwiftUIWeb

/// The search field, the add button and the two counts.
struct BoardToolbarView: View {
  let model: BoardModel
  let resultCount: Int

  var body: some View {
    HStack(spacing: 12) {
      TextField("Search works", text: Binding(get: { model.query }, set: { model.query = $0 }))
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("search")
      Button("Add work") { model.addWork() }.accessibilityIdentifier("add-button")
      Text("\(resultCount) results").accessibilityIdentifier("result-count")
      Text("\(model.favorites.count) favorites").accessibilityIdentifier("fav-count")
    }
    .frame(height: 48)
  }
}
