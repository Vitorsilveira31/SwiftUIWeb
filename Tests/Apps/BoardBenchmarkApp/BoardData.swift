import Foundation

/// One work of the board.
struct BoardWork: Identifiable, Equatable {
  let id: Int
  let title: String
  let status: String
}

/// The data of the board, generated exactly as `Benchmarks/ReactComparison/shared/data.mjs` generates it, so the React board
/// and this one answer every search with the same rows. A linear congruential generator makes it reproducible: each step is
/// `state = (state * 1103515245 + 12345) mod 2^31`, and work `i` takes three steps: the adjective, the noun and the status.
enum BoardData {
  static let workCount = 2000
  static let adjectives = ["Quiet", "Golden", "Broken", "Silent", "Crimson", "Hidden", "Last", "Lost", "Bright", "Paper", "Midnight", "Iron", "Velvet", "Distant", "Hollow", "Savage"]
  static let nouns = ["Harbor", "Garden", "Ledger", "Mirror", "Season", "Island", "Letter", "Engine", "Thread", "Winter", "Signal", "Orchard", "Empire", "Lantern", "Compass", "Archive"]
  static let statuses = ["Draft", "Review", "Approved", "Released"]

  static func makeWorks(_ count: Int = workCount) -> [BoardWork] {
    var state: UInt32 = 1_234_567
    func next() -> Int {
      state = (state &* 1_103_515_245 &+ 12_345) & 0x7fff_ffff
      return Int(state)
    }
    var works: [BoardWork] = []
    works.reserveCapacity(count)
    for index in 0..<count {
      let adjective = adjectives[next() % adjectives.count]
      let noun = nouns[next() % nouns.count]
      let status = statuses[next() % statuses.count]
      works.append(BoardWork(id: index + 1, title: "\(adjective) \(noun) \(index + 1)", status: status))
    }
    return works
  }

  /// The search of both apps: a case-insensitive substring of the title.
  static func matches(_ work: BoardWork, _ query: String) -> Bool {
    query.isEmpty || work.title.lowercased().contains(query.lowercased())
  }

  /// The cells of the stats view: a 20 by 10 grid whose numbers depend on how many works there are.
  static func statsCell(row: Int, column: Int, workCount: Int) -> Int {
    (row * 31 + column * 17 + workCount) % 97
  }
}
