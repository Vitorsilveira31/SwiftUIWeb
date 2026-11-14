/// Source of the prose the studies wrap around.
protocol WrapCopyRepository: Sendable {
    func text(_ study: WrapStudyText) -> WrapText
}
