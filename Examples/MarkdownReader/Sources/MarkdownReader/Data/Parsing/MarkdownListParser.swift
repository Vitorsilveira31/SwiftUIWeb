import Foundation

/// Reads one list item line: a bullet or number marker, an optional task
/// box, and the nesting depth from its indentation.
enum MarkdownListParser {
    struct Item {
        let depth: Int
        let marker: ListMarker
        let text: String
    }

    static func item(_ raw: String) -> Item? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        var marker: ListMarker
        var body: String
        if let first = text.first, "-*+".contains(first), text.count == 1 || text.dropFirst().first == " " {
            marker = .bullet
            body = String(text.dropFirst())
        } else {
            let digits = text.prefix(while: { $0.isNumber })
            guard (1...9).contains(digits.count),
                  let delimiter = text.dropFirst(digits.count).first,
                  delimiter == "." || delimiter == ")" else { return nil }
            let after = text.dropFirst(digits.count + 1)
            guard after.isEmpty || after.first == " " else { return nil }
            marker = .number(Int(digits) ?? 1)
            body = String(after)
        }
        body = body.trimmingCharacters(in: .whitespaces)
        for (box, checked) in [("[ ]", false), ("[x]", true), ("[X]", true)] where body.hasPrefix(box) {
            let rest = body.dropFirst(3)
            if rest.isEmpty || rest.first == " " {
                marker = .task(checked: checked)
                body = rest.trimmingCharacters(in: .whitespaces)
            }
        }
        // A nested list indents by two spaces per level, up to six levels.
        return Item(depth: min(MarkdownLineRecognizer.indentation(raw) / 2, 6), marker: marker, text: body)
    }
}
