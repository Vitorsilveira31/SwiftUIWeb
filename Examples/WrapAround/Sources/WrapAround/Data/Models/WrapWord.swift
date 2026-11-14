/// One word of prose, or a paragraph break (zero-size) that the layout reads as a line change.
struct WrapWord: Identifiable, Sendable {
    let id: Int
    let text: String
    var isBreak = false
}
