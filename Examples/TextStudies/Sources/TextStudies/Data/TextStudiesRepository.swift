/// The source of the studies' text. The app reads it through this protocol, so a different source
/// (a server, a file) can replace the bundled sample without touching the views or ViewModels.
protocol TextStudiesRepository: Sendable {
    func prose() -> ProseVO
    func cards(seed: Int, count: Int) -> [CardVO]
}
