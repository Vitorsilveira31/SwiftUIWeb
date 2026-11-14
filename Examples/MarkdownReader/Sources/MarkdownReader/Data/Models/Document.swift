/// A parsed document: its blocks, the blocks each in-document anchor names,
/// and the headings the contents sheet lists.
struct Document: Sendable, Equatable {
    var blocks: [Block] = []
    var anchors: [String: Int] = [:]
    var headings: [Heading] = []
}
