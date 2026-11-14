import Foundation

/// Recognisers for the single-line blocks: fences, headings, rules, images.
enum MarkdownLineRecognizer {
    static func fenceCharacter(_ text: String) -> Character? {
        guard text.count >= 3, let first = text.first, first == "`" || first == "~" else { return nil }
        return text.prefix(3).allSatisfy({ $0 == first }) ? first : nil
    }

    static func heading(_ text: String) -> (level: Int, title: String)? {
        let hashes = text.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = text.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var title = rest.trimmingCharacters(in: .whitespaces)
        // A run of closing hashes goes only when a space separates it from the words,
        // so `# C#` keeps its hash.
        var stripped = title
        while stripped.hasSuffix("#") {
            stripped.removeLast()
        }
        if stripped.isEmpty {
            title = ""
        } else if stripped.hasSuffix(" ") {
            title = stripped.trimmingCharacters(in: .whitespaces)
        }
        return (hashes, title)
    }

    static func isRule(_ text: String) -> Bool {
        let marks = text.filter { !$0.isWhitespace }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    static func image(_ text: String) -> (alt: String, source: String)? {
        guard text.hasPrefix("!["), text.hasSuffix(")"), let split = text.range(of: "](") else { return nil }
        let alt = text[text.index(text.startIndex, offsetBy: 2)..<split.lowerBound]
        let source = text[split.upperBound..<text.index(before: text.endIndex)]
        return (String(alt), String(source))
    }

    /// Leading spaces count one each, a tab four.
    static func indentation(_ line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " {
                width += 1
            } else if character == "\t" {
                width += 4
            } else {
                break
            }
        }
        return width
    }
}
