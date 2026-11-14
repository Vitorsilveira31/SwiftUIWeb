enum BlockKind: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case quote(depth: Int, text: String)
    case item(depth: Int, marker: ListMarker, text: String)
    case code(language: String, text: String)
    case table(TableData)
    case rule
    case image(alt: String, source: String)
}
