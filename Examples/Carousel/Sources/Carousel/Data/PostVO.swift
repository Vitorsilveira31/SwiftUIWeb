/// One row of the feed. Every fifth post holds a strip of cards, every seventh
/// an inbox of messages, the rest are plain text rows.
struct PostVO: Identifiable, Sendable {
    enum Kind: Sendable { case strip, inbox, text }

    let n: Int
    let kind: Kind
    let cards: [CardVO]

    var id: String { "p\(n)" }
}
