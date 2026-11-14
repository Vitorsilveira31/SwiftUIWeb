enum ListMarker: Sendable, Equatable {
    case bullet
    case number(Int)
    case task(checked: Bool)
}
