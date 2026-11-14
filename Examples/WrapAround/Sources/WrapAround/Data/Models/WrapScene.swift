/// The seven studies, in the order of the tab row.
enum WrapScene: String, CaseIterable, Identifiable, Sendable {
    case drag, orbs, dancer, ball, editorial, polygon, article

    var id: String { rawValue }
    var testId: String { "scene-\(rawValue)" }

    var label: String {
        switch self {
        case .drag: Strings.WrapAround.Drag.label
        case .orbs: Strings.WrapAround.Orbs.label
        case .dancer: Strings.WrapAround.Dancer.label
        case .ball: Strings.WrapAround.Ball.label
        case .editorial: Strings.WrapAround.Editorial.label
        case .polygon: Strings.WrapAround.Polygon.label
        case .article: Strings.WrapAround.Article.label
        }
    }

    var eyebrow: String {
        switch self {
        case .drag: Strings.WrapAround.Drag.eyebrow
        case .orbs: Strings.WrapAround.Orbs.eyebrow
        case .dancer: Strings.WrapAround.Dancer.eyebrow
        case .ball: Strings.WrapAround.Ball.eyebrow
        case .editorial: Strings.WrapAround.Editorial.eyebrow
        case .polygon: Strings.WrapAround.Polygon.eyebrow
        case .article: Strings.WrapAround.Article.eyebrow
        }
    }

    var title: String {
        switch self {
        case .drag: Strings.WrapAround.Drag.title
        case .orbs: Strings.WrapAround.Orbs.title
        case .dancer: Strings.WrapAround.Dancer.title
        case .ball: Strings.WrapAround.Ball.title
        case .editorial: Strings.WrapAround.Editorial.title
        case .polygon: Strings.WrapAround.Polygon.title
        case .article: Strings.WrapAround.Article.title
        }
    }

    var subtitle: String {
        switch self {
        case .drag: Strings.WrapAround.Drag.subtitle
        case .orbs: Strings.WrapAround.Orbs.subtitle
        case .dancer: Strings.WrapAround.Dancer.subtitle
        case .ball: Strings.WrapAround.Ball.subtitle
        case .editorial: Strings.WrapAround.Editorial.subtitle
        case .polygon: Strings.WrapAround.Polygon.subtitle
        case .article: Strings.WrapAround.Article.subtitle
        }
    }
}
