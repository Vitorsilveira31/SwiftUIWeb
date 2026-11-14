import SwiftUIWeb

/// A piece of a snippet: a word, or the space after it, and whether it is one the query asked for (bold).
struct SnippetRun: Equatable {
  let text: String
  let isMatch: Bool
}

/// A snippet with the words of the query in bold. Each run is its own `Text`, joined as `Text` values, never as one string.
enum SnippetRuns {
  static func runs(_ snippet: String, query: String) -> [SnippetRun] {
    let wanted = Set(query.split(separator: " ").map { bare(String($0)) })
    var runs: [SnippetRun] = []
    for (index, word) in snippet.split(separator: " ").enumerated() {
      if index > 0 { runs.append(SnippetRun(text: " ", isMatch: false)) }
      let text = String(word)
      runs.append(SnippetRun(text: text, isMatch: wanted.contains(bare(text))))
    }
    return runs
  }

  static func text(_ snippet: String, query: String) -> Text {
    var joined = Text("")
    for run in runs(snippet, query: query) {
      let piece = Text(run.text)
      joined = joined + (run.isMatch ? piece.fontWeight(.bold) : piece)
    }
    return joined
  }

  /// A word without its punctuation and case: "Harbor." and "harbor" are the same word.
  private static func bare(_ word: String) -> String {
    String(word.lowercased().filter { $0.isLetter || $0.isNumber })
  }
}
