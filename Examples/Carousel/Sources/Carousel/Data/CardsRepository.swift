/// Source of the Cards screen's content: the card strip and the feed rows.
protocol CardsRepository: Sendable {
    func cards(count: Int) -> [CardVO]
    func posts(count: Int) -> [PostVO]
}
