import SwiftUIWeb

/// One work: its title (tap to open it), its status and the favorite button.
struct BoardRowView: View {
  let work: BoardWork
  let isFavorite: Bool
  let isSelected: Bool
  let model: BoardModel

  var body: some View {
    HStack(spacing: 12) {
      Text(work.title)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onTapGesture { model.select(work.id) }
        .accessibilityIdentifier("title-\(work.id)")
      Text(work.status).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
      Button(isFavorite ? "★" : "☆") { model.toggleFavorite(work.id) }
        .accessibilityIdentifier("fav-\(work.id)")
    }
    .padding(.horizontal, 12)
    .frame(height: 44)
    .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
    .accessibilityIdentifier("row")
  }
}
