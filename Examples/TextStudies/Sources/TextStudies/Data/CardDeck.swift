/// Generates cards deterministically: the same (seed, index) always gives the same card.
enum CardDeck {
    /// The seed the wall is laid out with. The masonry study starts from the same seed and reshuffles.
    static let wallSeed = 1

    static func cards(seed: Int, count: Int) -> [CardVO] {
        (0..<count).map { card(seed: seed, index: $0) }
    }

    static func card(seed: Int, index: Int) -> CardVO {
        var state = (UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15)
            ^ ((UInt64(index) &+ 1) &* 0xD1B5_4A32_D192_ED03)
        let title = CardText.titles[Int(next(&state) % UInt64(CardText.titles.count))]
        let sentenceCount = 1 + Int(next(&state) % 4)
        var sentences: [String] = []
        for _ in 0..<sentenceCount {
            let pick = Int(next(&state) % UInt64(CardText.sentences.count))
            sentences.append(CardText.sentences[pick])
        }
        let body = sentences.joined(separator: " ")
        return CardVO(
            id: "\(seed)-\(index)",
            index: index,
            title: title,
            body: body,
            words: body.split(separator: " ").count)
    }

    private static func next(_ state: inout UInt64) -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
}
