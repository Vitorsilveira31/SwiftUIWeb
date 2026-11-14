/// The prose the text studies set, already split into the words the line breaker places.
struct ProseVO: Sendable {
    var ballWords: [String] = []
    var dragonWords: [String] = []
    var dropCapLetter = ""
    var pullQuote = ""
    var articleWords: [String] = []
    /// `articleBreaks[i]` is true when a paragraph ends after article word `i`.
    var articleBreaks: [Bool] = []
    /// The article with its first letter moved into the drop cap.
    var articleSpreadWords: [String] = []
}
