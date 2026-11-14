/// One person in the deck. `n` is the place in the deck, counted from 0 at the first card shown; the deck is sorted by it.
struct Profile: Identifiable, Hashable, Sendable {
    let n: Int
    let name: String
    let age: Int
    let job: String
    let miles: Int
    let bio: String
    let likesYou: Bool
    let interests: [String]

    /// Every profile has two portraits, drawn in code.
    static let photoCount = 2

    var id: String { "p\(n)" }
    var initial: String { String(name.prefix(1)) }
}
