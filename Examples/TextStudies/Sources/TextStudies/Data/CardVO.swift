/// A card in the masonry and the wall: its words are a pure function of (seed, index).
struct CardVO: Identifiable, Sendable {
    let id: String
    let index: Int
    let title: String
    let body: String
    let words: Int
}
