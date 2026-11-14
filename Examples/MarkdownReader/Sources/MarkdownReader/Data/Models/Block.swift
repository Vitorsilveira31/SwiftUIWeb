/// One block of a parsed document. The document is a flat list, not a tree:
/// nesting is a `depth`, so a lazy column can lay out one row per block.
struct Block: Identifiable, Sendable, Equatable {
    let id: Int
    let kind: BlockKind
}
