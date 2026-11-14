import Foundation

/// The line loop: decides which block each line starts or continues. Lists
/// and tables are read by their own parsers, the single-line forms by
/// `MarkdownLineRecognizer`.
struct MarkdownBlockScanner {
    /// Quotes nest at most this deep, as lists do.
    private static let maxQuoteDepth = 6

    private(set) var kinds: [BlockKind] = []
    private var paragraphLines: [String] = []
    private var quoteDepth = 0
    private var quoteLines: [String] = []
    /// Index in `kinds` of the list item that indented lines continue, while it is still open.
    private var openItem: Int?
    private var itemLines: [String] = []

    mutating func read(_ lines: [String]) {
        var index = 0
        while index < lines.count {
            let raw = lines[index]
            let text = raw.trimmingCharacters(in: .whitespaces)

            if text.isEmpty {
                flushQuote()
                flushParagraph()
                index += 1
                continue
            }
            if !text.hasPrefix(">") {
                flushQuote()
            }

            if let fence = MarkdownLineRecognizer.fenceCharacter(text) {
                flushParagraph()
                index = readFence(fence, opening: text, lines: lines, from: index + 1)
                continue
            }

            if let heading = MarkdownLineRecognizer.heading(text) {
                flushParagraph()
                append(.heading(level: heading.level, text: heading.title))
                index += 1
                continue
            }

            if MarkdownLineRecognizer.isRule(text) {
                flushParagraph()
                append(.rule)
                index += 1
                continue
            }

            if text.hasPrefix(">") {
                flushParagraph()
                addQuoteLine(text)
                index += 1
                continue
            }

            if let item = MarkdownListParser.item(raw) {
                flushParagraph()
                append(.item(depth: item.depth, marker: item.marker, text: item.text))
                openItem = kinds.count - 1
                index += 1
                continue
            }

            // Indented text after a list item continues that item.
            if MarkdownLineRecognizer.indentation(raw) >= 2, openItem != nil {
                itemLines.append(text)
                index += 1
                continue
            }

            if text.contains("|"), index + 1 < lines.count, MarkdownTableParser.isDelimiterRow(lines[index + 1]) {
                flushParagraph()
                let parsed = MarkdownTableParser.parse(lines, start: index)
                append(.table(parsed.table))
                index = parsed.next
                continue
            }

            if let image = MarkdownLineRecognizer.image(text) {
                flushParagraph()
                append(.image(alt: image.alt, source: image.source))
                index += 1
                continue
            }

            appendToParagraph(text)
            index += 1
        }
        flushQuote()
        flushParagraph()
        closeItem()
    }

    /// Fenced code keeps its lines exactly as written, up to the closing fence.
    /// Returns the index of the line after the block.
    private mutating func readFence(_ fence: Character, opening text: String, lines: [String], from start: Int) -> Int {
        let language = String(text.drop(while: { $0 == fence })).trimmingCharacters(in: .whitespaces)
        var code: [String] = []
        var index = start
        while index < lines.count {
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            if candidate.count >= 3, candidate.allSatisfy({ $0 == fence }) {
                index += 1
                break
            }
            code.append(lines[index])
            index += 1
        }
        append(.code(language: language, text: code.joined(separator: "\n")))
        return index
    }

    private mutating func addQuoteLine(_ text: String) {
        var depth = 0
        var rest = Substring(text)
        while rest.first == ">" {
            depth = min(depth + 1, Self.maxQuoteDepth)
            rest = rest.dropFirst()
            if rest.first == " " {
                rest = rest.dropFirst()
            }
        }
        let body = rest.trimmingCharacters(in: .whitespaces)
        if body.isEmpty {
            flushQuote()
        } else if depth == quoteDepth, !quoteLines.isEmpty {
            quoteLines.append(body)
        } else {
            flushQuote()
            quoteDepth = depth
            quoteLines = [body]
        }
    }

    private mutating func appendToParagraph(_ text: String) {
        paragraphLines.append(text)
    }

    private mutating func flushParagraph() {
        guard !paragraphLines.isEmpty else { return }
        append(.paragraph(text: paragraphLines.joined(separator: " ")))
        paragraphLines = []
    }

    private mutating func flushQuote() {
        guard !quoteLines.isEmpty else { return }
        append(.quote(depth: quoteDepth, text: quoteLines.joined(separator: " ")))
        quoteLines = []
    }

    /// Every block goes through here, so an open list item is finished before the next block starts.
    private mutating func append(_ kind: BlockKind) {
        closeItem()
        kinds.append(kind)
    }

    /// Writes the item's continuation lines in one join, not once per line.
    private mutating func closeItem() {
        guard let index = openItem else { return }
        if case let .item(depth, marker, first) = kinds[index] {
            kinds[index] = .item(depth: depth, marker: marker, text: ([first] + itemLines).joined(separator: " "))
        }
        openItem = nil
        itemLines = []
    }
}
