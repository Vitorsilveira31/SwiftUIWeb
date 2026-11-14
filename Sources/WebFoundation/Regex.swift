// The standard library's `Regex`, which Embedded Swift does not ship. Runtime patterns (`try Regex("max_id=[0-9]+")`)
// are compiled by a small backtracking matcher: literals, `.`, classes, `\d \w \s \b`, anchors, groups,
// alternation and the greedy/lazy quantifiers. Regex literals (`/…/`) are a compiler feature and are not available.
indirect enum RegexNode {
  case char(Character)
  case any
  case set(items: [RegexClassItem], negated: Bool)
  case sequence([RegexNode])
  case alternation([RegexNode])
  case group(RegexNode, index: Int?)
  case repeating(RegexNode, min: Int, max: Int, greedy: Bool)
  case lineStart, lineEnd, wordBoundary
}

enum RegexClassItem {
  case range(Character, Character)
  case digit, word, space
  case notDigit, notWord, notSpace
}

public struct RegexSyntaxError: Error { public let message: String }

struct RegexProgram {
  let root: RegexNode
  let groupCount: Int
  let options: RegexOptions

  init(pattern: String) throws {
    var parser = RegexParser(Array(pattern))
    root = try parser.parseAlternation()
    guard parser.index >= parser.chars.count else { throw RegexSyntaxError(message: "unbalanced parenthesis") }
    groupCount = parser.groups
    options = parser.options
  }

  /// Capture ranges (index 0 is the whole match) of the first match at or after `start`. One matcher, and so one step
  /// budget, serves every starting position.
  func firstMatch(in chars: [Character], from start: Int = 0) -> [Range<Int>?]? {
    let matcher = RegexMatcher(chars: chars, groups: groupCount + 1, options: options)
    var begin = start
    while begin <= chars.count, !matcher.exhausted {
      matcher.reset()
      var end = -1
      if matcher.match(root, begin, { end = $0; return true }) {
        matcher.captures[0] = begin..<end
        return matcher.captures
      }
      begin += 1
    }
    return nil
  }

  /// Capture ranges of a match that spans all of `chars`. The continuation rejects every shorter match, so the
  /// backtracking matcher keeps looking for one that reaches the end.
  func wholeMatch(in chars: [Character]) -> [Range<Int>?]? {
    let matcher = RegexMatcher(chars: chars, groups: groupCount + 1, options: options)
    guard matcher.match(root, 0, { $0 == chars.count }) else { return nil }
    matcher.captures[0] = 0 ..< chars.count
    return matcher.captures
  }
}

/// The inline options a pattern sets with `(?i)`, `(?m)` and `(?s)`, as Swift's `Regex` reads them: case-insensitive,
/// `^` and `$` at line breaks (`anchorsMatchLineEndings()`; by default only at the start and end of the input), and `.`
/// matching a line break (`dotMatchesNewlines()`).
struct RegexOptions {
  var ignoresCase = false
  var multiline = false
  var dotMatchesNewlines = false
}

struct RegexParser {
  let chars: [Character]
  var index = 0
  var groups = 0
  var options = RegexOptions()
  /// How many groups are open: a pattern from data nesting thousands deep would overflow the browser's stack while
  /// parsing and matching.
  var depth = 0
  static let depthLimit = 100

  init(_ chars: [Character]) { self.chars = chars }

  mutating func parseAlternation() throws -> RegexNode {
    var branches = [try parseSequence()]
    while index < chars.count, chars[index] == "|" {
      index += 1
      branches.append(try parseSequence())
    }
    return branches.count == 1 ? branches[0] : .alternation(branches)
  }

  mutating func parseSequence() throws -> RegexNode {
    var items: [RegexNode] = []
    while index < chars.count, chars[index] != "|", chars[index] != ")" {
      var atom = try parseAtom()
      atom = try parseQuantifier(atom)
      items.append(atom)
    }
    return .sequence(items)
  }

  mutating func parseQuantifier(_ atom: RegexNode) throws -> RegexNode {
    guard index < chars.count else { return atom }
    var low = 0, high = Int.max
    switch chars[index] {
    case "*": index += 1
    case "+": low = 1; index += 1
    case "?": high = 1; index += 1
    case "{":
      // A bound is a few digits: looking further for its "}" would make a pattern of many "{" quadratic.
      guard let close = chars[index ..< min(chars.count, index + 24)].firstIndex(of: "}") else { return atom }
      let parts = String(chars[(index + 1)..<close]).split(separator: ",", omittingEmptySubsequences: false)
      guard let first = parts.first, let parsedLow = Int(first) else { return atom }
      low = parsedLow
      high = parts.count == 1 ? parsedLow : (Int(parts[1]) ?? Int.max)
      index = close + 1
    default: return atom
    }
    var greedy = true
    if index < chars.count, chars[index] == "?" { greedy = false; index += 1 }
    return .repeating(atom, min: low, max: high, greedy: greedy)
  }

  mutating func parseAtom() throws -> RegexNode {
    let char = chars[index]
    index += 1
    switch char {
    case ".": return .any
    case "^": return .lineStart
    case "$": return .lineEnd
    case "(":
      var capture: Int? = nil
      if index + 1 < chars.count, chars[index] == "?" {
        if chars[index + 1] == ":" { index += 2 }
        else if let close = chars[(index + 1)...].prefix(4).firstIndex(of: ")"),
                close > index + 1, chars[(index + 1)..<close].allSatisfy({ "ims".contains($0) }) {
          // (?i), (?m), (?s) and their combinations: options for the rest of the pattern.
          for flag in chars[(index + 1)..<close] {
            switch flag {
            case "i": options.ignoresCase = true
            case "m": options.multiline = true
            default: options.dotMatchesNewlines = true
            }
          }
          index = close + 1
          return .sequence([])
        } else { throw RegexSyntaxError(message: "unsupported group") }
      } else {
        groups += 1
        capture = groups
      }
      depth += 1
      defer { depth -= 1 }
      guard depth <= Self.depthLimit else { throw RegexSyntaxError(message: "groups nested too deeply") }
      let inner = try parseAlternation()
      guard index < chars.count, chars[index] == ")" else { throw RegexSyntaxError(message: "missing )") }
      index += 1
      return .group(inner, index: capture)
    case "[": return try parseSet()
    case "\\": return try parseEscape(inSet: false).node
    default: return .char(char)
    }
  }

  mutating func parseEscape(inSet: Bool) throws -> (node: RegexNode, item: RegexClassItem?) {
    guard index < chars.count else { throw RegexSyntaxError(message: "trailing backslash") }
    let char = chars[index]
    index += 1
    func item(_ value: RegexClassItem) -> (RegexNode, RegexClassItem?) { (.set(items: [value], negated: false), value) }
    switch char {
    case "d": return item(.digit)
    case "D": return item(.notDigit)
    case "w": return item(.word)
    case "W": return item(.notWord)
    case "s": return item(.space)
    case "S": return item(.notSpace)
    case "b" where !inSet: return (.wordBoundary, nil)
    case "n": return (.char("\n"), .range("\n", "\n"))
    case "t": return (.char("\t"), .range("\t", "\t"))
    default: return (.char(char), .range(char, char))
    }
  }

  mutating func parseSet() throws -> RegexNode {
    var negated = false
    if index < chars.count, chars[index] == "^" { negated = true; index += 1 }
    var items: [RegexClassItem] = []
    var first = true
    while index < chars.count, first || chars[index] != "]" {
      first = false
      var low = chars[index]
      index += 1
      if low == "\\" {
        let escape = try parseEscape(inSet: true)
        guard let item = escape.item else { continue }
        if case .range(let value, _) = item { low = value } else { items.append(item); continue }
      }
      if index + 1 < chars.count, chars[index] == "-", chars[index + 1] != "]" {
        index += 1
        var high = chars[index]
        index += 1
        if high == "\\" { if case .range(let value, _)? = try parseEscape(inSet: true).item { high = value } }
        items.append(.range(low, high))
      } else {
        items.append(.range(low, low))
      }
    }
    guard index < chars.count else { throw RegexSyntaxError(message: "missing ]") }
    index += 1
    return .set(items: items, negated: negated)
  }
}

final class RegexMatcher {
  let chars: [Character]
  let ignoresCase: Bool
  let options: RegexOptions
  var captures: [Range<Int>?]
  /// Steps taken by the whole search. A backtracking pattern such as `(a+)+$` takes exponential time on a text from data;
  /// past the budget the search fails (no match) instead of freezing the page. The budget grows with the text, so an
  /// ordinary search of a long text (a few steps per position) always finishes, while an exponential one does not.
  private var steps = 0
  static let stepLimit = 2_000_000
  /// Steps allowed per character of the text, on top of `stepLimit`.
  static let stepsPerCharacter = 64
  /// The most steps any one search takes, whatever the text's length: a finite limit even where `Int` is 32 bits.
  static let stepCeiling = 200_000_000
  private let budget: Int
  var exhausted: Bool { steps > budget }
  private let groupCount: Int
  /// How deep the backtracking is. Every step of the continuation-passing matcher is a stack frame, and the browser's
  /// stack ends at about 1,500 levels of this matcher in a worker (a group repeated 350 times): a match that would go
  /// deeper than 600 fails instead of stopping the application.
  /// A repeated single character (`a+`, `.*`, `[a-z]+`) is matched in a loop and takes no depth per repetition.
  private var depth = 0
  static let depthLimit = 600

  init(chars: [Character], groups: Int, options: RegexOptions) {
    self.chars = chars
    self.options = options
    ignoresCase = options.ignoresCase
    groupCount = groups
    captures = Array(repeating: nil, count: groups)
    let (scaled, overflow) = chars.count.multipliedReportingOverflow(by: Self.stepsPerCharacter)
    budget = overflow ? Self.stepCeiling : Swift.min(Self.stepCeiling, Self.stepLimit + Swift.min(scaled, Self.stepCeiling))
  }

  /// Clears the captures for a search from another position; the step budget carries on.
  func reset() { captures = Array(repeating: nil, count: groupCount) }

  private func isWord(_ char: Character) -> Bool { char.isLetter || char.isNumber || char == "_" }

  private func matches(_ item: RegexClassItem, _ char: Character) -> Bool {
    switch item {
    case .range(let low, let high):
      if char >= low && char <= high { return true }
      guard ignoresCase else { return false }
      // A case mapping can be longer than one character ("ß" uppercases to "SS"); such a character matches as itself.
      let lowered = char.lowercased(), uppered = char.uppercased()
      let lower = lowered.count == 1 ? lowered.first ?? char : char
      let upper = uppered.count == 1 ? uppered.first ?? char : char
      return (lower >= low && lower <= high) || (upper >= low && upper <= high)
    case .digit: return char.isASCII && char.isNumber
    case .notDigit: return !(char.isASCII && char.isNumber)
    case .word: return isWord(char)
    case .notWord: return !isWord(char)
    case .space: return char.isWhitespace
    case .notSpace: return !char.isWhitespace
    }
  }

  func match(_ node: RegexNode, _ at: Int, _ next: (Int) -> Bool) -> Bool {
    guard depth < Self.depthLimit else { return false }
    steps += 1
    guard steps <= budget else { return false }
    depth += 1
    defer { depth -= 1 }
    switch node {
    case .char(let expected):
      guard at < chars.count else { return false }
      let actual = chars[at]
      let same = actual == expected || (ignoresCase && actual.lowercased() == expected.lowercased())
      return same && next(at + 1)
    case .any:
      return at < chars.count && (options.dotMatchesNewlines || !chars[at].isNewline) && next(at + 1)
    case .set(let items, let negated):
      guard at < chars.count else { return false }
      let char = chars[at]
      var hit = false
      for item in items where matches(item, char) { hit = true; break }
      return hit != negated && next(at + 1)
    case .sequence(let nodes):
      return matchSequence(nodes, 0, at, next)
    case .alternation(let branches):
      for branch in branches where match(branch, at, next) { return true }
      return false
    case .group(let inner, let index):
      let previous = index.flatMap { captures[$0] }
      let matched = match(inner, at) { end in
        if let index { captures[index] = at..<end }
        if next(end) { return true }
        if let index { captures[index] = previous }
        return false
      }
      return matched
    case .repeating(let inner, let low, let high, let greedy):
      return matchRepeat(inner, low, high, greedy, 0, at, next)
    case .lineStart:
      return (at == 0 || options.multiline && chars[at - 1].isNewline) && next(at)
    case .lineEnd:
      return (at == chars.count || options.multiline && chars[at].isNewline) && next(at)
    case .wordBoundary:
      let before = at > 0 && isWord(chars[at - 1])
      let after = at < chars.count && isWord(chars[at])
      return before != after && next(at)
    }
  }

  private func matchSequence(_ nodes: [RegexNode], _ position: Int, _ at: Int, _ next: (Int) -> Bool) -> Bool {
    // A run of one-character elements (literals, `.`, classes) matches one way only, so it is walked in a loop: a long
    // literal pattern takes no depth per character and is not refused by the depth limit.
    var position = position, at = at
    while position < nodes.count, let one = matchesOne(nodes[position], at) {
      steps += 1
      guard one, steps <= budget else { return false }
      position += 1
      at += 1
    }
    guard position < nodes.count else { return next(at) }
    return match(nodes[position], at) { matchSequence(nodes, position + 1, $0, next) }
  }

  /// Whether `node` matches exactly the one character at `at`, for a node that is one character wide.
  private func matchesOne(_ node: RegexNode, _ at: Int) -> Bool? {
    guard at < chars.count else {
      switch node { case .char, .any, .set: return false; default: return nil }
    }
    switch node {
    case .char(let expected):
      let actual = chars[at]
      return actual == expected || (ignoresCase && actual.lowercased() == expected.lowercased())
    case .any:
      return options.dotMatchesNewlines || !chars[at].isNewline
    case .set(let items, let negated):
      var hit = false
      for item in items where matches(item, chars[at]) { hit = true; break }
      return hit != negated
    default:
      return nil
    }
  }

  private func matchRepeat(_ node: RegexNode, _ low: Int, _ high: Int, _ greedy: Bool, _ count: Int, _ at: Int, _ next: (Int) -> Bool) -> Bool {
    // One character wide: count how far it runs, then try the continuation from each length, longest first when greedy.
    if count == 0, matchesOne(node, at) != nil {
      // Each character read and each continuation tried counts against the step budget, as a recursive step does.
      func step() -> Bool {
        steps += 1
        return steps <= budget
      }
      if greedy {
        var run = 0
        while run < high, matchesOne(node, at + run) == true {
          guard step() else { return false }
          run += 1
        }
        guard run >= low else { return false }
        var length = run
        while length >= low {
          guard step() else { return false }
          if next(at + length) { return true }
          length -= 1
        }
        return false
      }
      // Lazy: the shortest length first, and one more character only when the continuation fails, so a match that
      // succeeds at once does not read the whole run (which made matching every position of "aaaa..." quadratic).
      var length = 0
      while length < low {
        guard step(), matchesOne(node, at + length) == true else { return false }
        length += 1
      }
      while true {
        guard step() else { return false }
        if next(at + length) { return true }
        guard length < high, matchesOne(node, at + length) == true else { return false }
        length += 1
      }
    }
    func more() -> Bool {
      guard count < high else { return false }
      return match(node, at) { end in
        end == at && count >= low ? false : matchRepeat(node, low, high, greedy, count + 1, end, next)
      }
    }
    if count < low { return more() }
    if greedy { return more() || next(at) }
    return next(at) || more()
  }
}

// MARK: - Public surface

public struct AnyRegexOutput: RandomAccessCollection {
  public struct Element {
    public let substring: Substring?
  }
  let elements: [Element]
  public var startIndex: Int { 0 }
  public var endIndex: Int { elements.count }
  public subscript(position: Int) -> Element { elements[position] }
}

public struct Regex<Output> {
  let program: RegexProgram

  public struct Match {
    public let output: Output
    public let range: Range<String.Index>
  }
}

extension Regex where Output == AnyRegexOutput {
  public init(_ pattern: String) throws { program = try RegexProgram(pattern: pattern) }
}

extension StringProtocol {
  public func firstMatch(of regex: Regex<AnyRegexOutput>) -> Regex<AnyRegexOutput>.Match? {
    let text = String(self)
    let chars = Array(text)
    guard let captures = regex.program.firstMatch(in: chars) else { return nil }
    let elements = captures.map { range -> AnyRegexOutput.Element in
      guard let range else { return AnyRegexOutput.Element(substring: nil) }
      return AnyRegexOutput.Element(substring: Substring(String(chars[range])))
    }
    let whole = captures[0]!
    let lower = text.index(text.startIndex, offsetBy: whole.lowerBound)
    let upper = text.index(text.startIndex, offsetBy: whole.upperBound)
    return Regex<AnyRegexOutput>.Match(output: AnyRegexOutput(elements: elements), range: lower..<upper)
  }

  /// The match of `regex` that spans the whole string, or `nil` (Swift's `wholeMatch(of:)`).
  public func wholeMatch(of regex: Regex<AnyRegexOutput>) -> Regex<AnyRegexOutput>.Match? {
    let text = String(self)
    let chars = Array(text)
    guard let captures = regex.program.wholeMatch(in: chars) else { return nil }
    let elements = captures.map { range -> AnyRegexOutput.Element in
      guard let range else { return AnyRegexOutput.Element(substring: nil) }
      return AnyRegexOutput.Element(substring: Substring(String(chars[range])))
    }
    return Regex<AnyRegexOutput>.Match(output: AnyRegexOutput(elements: elements), range: text.startIndex..<text.endIndex)
  }
}

extension StringProtocol {
  public func matches(of regex: Regex<AnyRegexOutput>) -> [Regex<AnyRegexOutput>.Match] {
    let text = String(self)
    let chars = Array(text)
    var result: [Regex<AnyRegexOutput>.Match] = []
    var position = 0
    // The string index of every character offset, once: walking from the start for each match was O(n) per match.
    let indices = Array(text.indices) + [text.endIndex]
    while position <= chars.count, let captures = regex.program.firstMatch(in: chars, from: position) {
      let whole = captures[0]!
      let elements = captures.map { range -> AnyRegexOutput.Element in
        guard let range else { return AnyRegexOutput.Element(substring: nil) }
        return AnyRegexOutput.Element(substring: Substring(String(chars[range])))
      }
      result.append(Regex<AnyRegexOutput>.Match(output: AnyRegexOutput(elements: elements), range: indices[whole.lowerBound]..<indices[whole.upperBound]))
      position = whole.upperBound > whole.lowerBound ? whole.upperBound : whole.upperBound + 1
    }
    return result
  }

  public func contains(_ regex: Regex<AnyRegexOutput>) -> Bool { firstMatch(of: regex) != nil }

  /// The pieces between matches of `separator`.
  public func split(separator: Regex<AnyRegexOutput>, omittingEmptySubsequences: Bool = true) -> [Substring] {
    let text = String(self)
    var pieces: [Substring] = []
    var start = text.startIndex
    for match in matches(of: separator) {
      pieces.append(text[start..<match.range.lowerBound])
      start = match.range.upperBound
    }
    pieces.append(text[start...])
    return omittingEmptySubsequences ? pieces.filter { !$0.isEmpty } : pieces
  }

  public func replacing(_ target: String, with replacement: String) -> String {
    String(self).replacingOccurrences(of: target, with: replacement)
  }

  public func replacing(_ regex: Regex<AnyRegexOutput>, with replacement: String) -> String {
    let text = String(self)
    var result = ""
    var start = text.startIndex
    for match in matches(of: regex) {
      result += text[start..<match.range.lowerBound]
      result += replacement
      start = match.range.upperBound
    }
    return result + text[start...]
  }
}
