/// The seven studies, in menu order.
enum TextStudy: String, CaseIterable, Identifiable, Sendable {
    case balls, dragon, masonry, magazine, ascii, wall, spread

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balls: Strings.Root.Study.balls
        case .dragon: Strings.Root.Study.dragon
        case .masonry: Strings.Root.Study.masonry
        case .magazine: Strings.Root.Study.magazine
        case .ascii: Strings.Root.Study.ascii
        case .wall: Strings.Root.Study.wall
        case .spread: Strings.Root.Study.spread
        }
    }
}
