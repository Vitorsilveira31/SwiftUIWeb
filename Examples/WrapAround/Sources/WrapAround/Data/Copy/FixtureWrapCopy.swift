/// The prose shipped with the app.
struct FixtureWrapCopy: WrapCopyRepository {
    func text(_ study: WrapStudyText) -> WrapText {
        switch study {
        case .drag: WrapCopy.drag
        case .orbs: WrapCopy.orbs
        case .dancer: WrapCopy.dancer
        case .ball: WrapCopy.ball
        case .polygon: WrapCopy.polygon
        case .editorialLeft: WrapCopy.editorialLeft
        case .editorialRight: WrapCopy.editorialRight
        case .article: WrapCopy.article
        }
    }
}
