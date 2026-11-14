// A grid tile or a dock item. A nil target says the app is not in the demo.
struct Tile: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let target: Destination?
}
