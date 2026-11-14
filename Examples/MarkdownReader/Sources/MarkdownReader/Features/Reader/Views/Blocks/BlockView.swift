import SwiftUI

/// Draws one block by its kind.
struct BlockView: View {
    let block: Block

    var body: some View {
        switch block.kind {
        case let .heading(level, text):
            HeadingBlockView(level: level, text: text)
        case let .paragraph(text):
            ParagraphBlockView(text: text)
        case let .quote(depth, text):
            QuoteBlockView(depth: depth, text: text)
        case let .item(depth, marker, text):
            ListItemBlockView(depth: depth, marker: marker, text: text)
        case let .code(language, text):
            CodeBlockView(language: language, code: text)
        case let .table(table):
            TableBlockView(table: table)
        case .rule:
            Divider()
                .padding(.vertical, 6)
        case let .image(alt, source):
            ImageBlockView(alt: alt, source: source)
        }
    }
}
