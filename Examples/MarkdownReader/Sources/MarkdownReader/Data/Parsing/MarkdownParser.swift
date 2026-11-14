import Foundation

/// Turns Markdown source into a `Document`. The subset it reads is headings,
/// paragraphs, nested quotes and lists with task items, fenced code, pipe
/// tables, rules and images. It never fails: anything else becomes paragraph text.
enum MarkdownParser {
    static func parse(_ source: String) -> Document {
        // `isNewline` also splits CRLF, which is one Character and would not
        // match a split on "\n".
        let lines = source
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { String($0) }
        var scanner = MarkdownBlockScanner()
        scanner.read(lines)
        return MarkdownDocumentIndex.document(from: scanner.kinds)
    }
}
