import SwiftUIWeb

enum BoardScreen {
  case board
  case stats
}

/// The state of the board: the works, the search, the favorites, the selection and the screen.
@MainActor @Observable
final class BoardModel {
  private(set) var works = BoardData.makeWorks()
  var query = ""
  private(set) var favorites: Set<Int> = []
  private(set) var selectedID: Int?
  var screen: BoardScreen = .board
  private var added = 0

  var visible: [BoardWork] { works.filter { BoardData.matches($0, query) } }
  var selected: BoardWork? { works.first { $0.id == selectedID } }

  func toggleFavorite(_ id: Int) {
    if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
  }

  func select(_ id: Int) { selectedID = id }

  func addWork() {
    added += 1
    works.insert(BoardWork(id: 2000 + added, title: "New work \(added)", status: "Draft"), at: 0)
  }
}
