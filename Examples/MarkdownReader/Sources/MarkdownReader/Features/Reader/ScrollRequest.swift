/// Asks the document to scroll. The serial makes a repeated jump to the same
/// block a new change, which `onChange` would otherwise drop.
struct ScrollRequest: Sendable, Equatable {
    let blockID: Int
    let serial: Int
}
