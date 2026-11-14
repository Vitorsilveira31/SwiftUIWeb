/// The bundled sample text: original prose and card text written for this demo.
struct SampleTextRepository: TextStudiesRepository {
    func prose() -> ProseVO {
        SampleProse.make()
    }

    func cards(seed: Int, count: Int) -> [CardVO] {
        CardDeck.cards(seed: seed, count: count)
    }
}
