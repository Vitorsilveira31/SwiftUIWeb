import Foundation

/// Numbers the blocks and indexes the headings, which the contents sheet and
/// the in-document `#anchor` links both use.
enum MarkdownDocumentIndex {
    static func document(from kinds: [BlockKind]) -> Document {
        var document = Document()
        document.blocks = kinds.enumerated().map { Block(id: $0.offset, kind: $0.element) }
        for block in document.blocks {
            guard case let .heading(level, text) = block.kind else { continue }
            let title = MarkdownInlineStyler.plainText(text)
            document.headings.append(Heading(id: block.id, level: level, title: title))
            let key = anchor(for: title)
            if !key.isEmpty, document.anchors[key] == nil {
                document.anchors[key] = block.id
            }
        }
        return document
    }

    /// The slug an in-document `#link` names: lower-case letters and digits,
    /// with spaces and hyphens joined by hyphens.
    static func anchor(for title: String) -> String {
        var slug = ""
        for character in title.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
            } else if character == " " || character == "-" {
                slug.append("-")
            }
        }
        return slug
    }
}
