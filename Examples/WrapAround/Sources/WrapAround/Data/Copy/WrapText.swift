/// The words of one prose text: the wide-column version and a shorter one for narrow screens.
struct WrapText: Sendable {
    let wide: [WrapWord]
    let narrow: [WrapWord]

    init(wide: [String], narrow: [String]? = nil) {
        self.wide = WrapText.split(wide)
        self.narrow = WrapText.split(narrow ?? wide)
    }

    func words(narrow isNarrow: Bool) -> [WrapWord] {
        isNarrow ? narrow : wide
    }

    /// Splits paragraphs into words, with a break between paragraphs.
    private static func split(_ paragraphs: [String]) -> [WrapWord] {
        var out: [WrapWord] = []
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 { out.append(WrapWord(id: out.count, text: "", isBreak: true)) }
            for word in paragraph.split(separator: " ") {
                out.append(WrapWord(id: out.count, text: String(word)))
            }
        }
        return out
    }
}
