/// Deterministic sample content: five widths cycling by index, six hues.
struct SampleCardsRepository: CardsRepository {
    private static let widths: [Double] = [96, 120, 160, 120, 200]

    func cards(count: Int) -> [CardVO] {
        (0..<count).map { makeCard($0) }
    }

    func posts(count: Int) -> [PostVO] {
        (0..<count).map { makePost($0) }
    }

    private func makeCard(_ n: Int) -> CardVO {
        CardVO(n: n, width: Self.widths[n % 5], hue: n % 6)
    }

    private func makePost(_ n: Int) -> PostVO {
        if n % 5 == 0 {
            return PostVO(n: n, kind: .strip, cards: cards(count: 200))
        }
        if n % 7 == 0 {
            return PostVO(n: n, kind: .inbox, cards: cards(count: 120))
        }
        return PostVO(n: n, kind: .text, cards: [])
    }
}
