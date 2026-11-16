@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable
// Foundation's `AttributedString`, on every host. Attributes are stored per character and grouped into
// runs on demand; `Text(AttributedString)` renders the runs (AttributedText.swift).

/// Internal access to a uniform view of, and a mutation hook over, an
/// attribute holder. Gives the three holders one set of typed properties.
public protocol _AttributeAccess {
  func _readAttributes() -> _TextAttributes
  mutating func _modifyAttributes(_ body: (inout _TextAttributes) -> Void)
}

extension _AttributeAccess {
  public var kern: Double? {
    get { _readAttributes().kern }
    set { let value = newValue; _modifyAttributes { $0.kern = value } }
  }
  public var tracking: Double? {
    get { _readAttributes().tracking }
    set { let value = newValue; _modifyAttributes { $0.tracking = value } }
  }
  public var foregroundColor: Color? {
    get { _readAttributes().foregroundColor }
    set { let value = newValue; _modifyAttributes { $0.foregroundColor = value } }
  }
  public var backgroundColor: Color? {
    get { _readAttributes().backgroundColor }
    set { let value = newValue; _modifyAttributes { $0.backgroundColor = value } }
  }
  public var font: Font? {
    get { _readAttributes().fontStyles.map { Font(cssStyles: $0) } }
    set { let value = newValue?.cssStyles; _modifyAttributes { $0.fontStyles = value } }
  }
  public var underlineStyle: Text.LineStyle? {
    get { _readAttributes().underlineStyle }
    set { let value = newValue; _modifyAttributes { $0.underlineStyle = value } }
  }
  public var strikethroughStyle: Text.LineStyle? {
    get { _readAttributes().strikethroughStyle }
    set { let value = newValue; _modifyAttributes { $0.strikethroughStyle = value } }
  }
  public var link: URL? {
    get { _readAttributes().linkString.flatMap { URL(string: $0) } }
    set { let value = newValue?.absoluteString; _modifyAttributes { $0.linkString = value } }
  }
  public var baselineOffset: Double? {
    get { _readAttributes().baselineOffset }
    set { let value = newValue; _modifyAttributes { $0.baselineOffset = value } }
  }
  /// The emphasis, code and strikethrough a run was written with (`AttributedString(markdown:)` sets it).
  public var inlinePresentationIntent: InlinePresentationIntent? {
    get { _readAttributes().inlineIntent }
    set { let value = newValue; _modifyAttributes { $0.inlineIntent = value } }
  }
}

/// Foundation's `InlinePresentationIntent`: the inline presentation of a run of text. The raw values are the ones
/// `NSInlinePresentationIntent` uses.
public struct InlinePresentationIntent: OptionSet, Hashable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }
  public static let emphasized = InlinePresentationIntent(rawValue: 1 << 0)
  public static let stronglyEmphasized = InlinePresentationIntent(rawValue: 1 << 1)
  public static let code = InlinePresentationIntent(rawValue: 1 << 2)
  public static let strikethrough = InlinePresentationIntent(rawValue: 1 << 5)
  public static let softBreak = InlinePresentationIntent(rawValue: 1 << 6)
  public static let lineBreak = InlinePresentationIntent(rawValue: 1 << 7)
  public static let inlineHTML = InlinePresentationIntent(rawValue: 1 << 8)
  public static let blockHTML = InlinePresentationIntent(rawValue: 1 << 9)
}

/// A set of attributes to apply to, or merge into, attributed text.
public struct AttributeContainer: Equatable, Sendable, _AttributeAccess {
  var _attributes = _TextAttributes()
  public init() {}
  public func _readAttributes() -> _TextAttributes { _attributes }
  public mutating func _modifyAttributes(_ body: (inout _TextAttributes) -> Void) { body(&_attributes) }
}

/// Foundation's `AttributedStringProtocol`: what `AttributedString` and `AttributedSubstring` share.
public protocol AttributedStringProtocol: CustomStringConvertible, Sendable {
  var startIndex: AttributedString.Index { get }
  var endIndex: AttributedString.Index { get }
  /// The characters and attributes between `startIndex` and `endIndex`, as their own string.
  var _flattened: AttributedString { get }
}

extension AttributedStringProtocol {
  public var description: String { _flattened.characters }

  /// The first range whose characters equal `stringToFind`'s (ignoring case with `.caseInsensitive`, the last one with
  /// `.backwards`), or nil. The locale is accepted for source compatibility; matching is locale-independent here.
  public func range<T: StringProtocol>(
    of stringToFind: T, options: String.CompareOptions = [], locale: Locale? = nil
  ) -> Range<AttributedString.Index>? {
    let folds = options.contains(.caseInsensitive)
    // A lowercase mapping longer than one character keeps the character itself rather than trapping Character(_:).
    let haystack = _flattened._characters.map { character -> Character in
      guard folds else { return character }
      let lowered = String(character).lowercased()
      return lowered.count == 1 ? lowered.first ?? character : character
    }
    let needle = Array(folds ? String(stringToFind).lowercased() : String(stringToFind))
    guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
    let lastStart = haystack.count - needle.count
    let backwards = options.contains(.backwards)
    let start: Int?
    if options.contains(.anchored) {
      let candidate = backwards ? lastStart : 0
      start = haystack[candidate ..< candidate + needle.count].elementsEqual(needle) ? candidate : nil
    } else if backwards {
      // The last occurrence is the first one in the reversed text.
      start = _firstOccurrence(of: needle.reversed(), in: haystack.reversed()).map { haystack.count - $0 - needle.count }
    } else {
      start = _firstOccurrence(of: needle, in: haystack)
    }
    guard let start else { return nil }
    let base = startIndex.offset
    return AttributedString.Index(offset: base + start) ..< AttributedString.Index(offset: base + start + needle.count)
  }
}

/// The offset of the first `needle` in `haystack`, by Knuth-Morris-Pratt: linear in both, where comparing at every start
/// is quadratic for a text such as "aaaa...ab" searched for "aaab".
private func _firstOccurrence(of needle: [Character], in haystack: [Character]) -> Int? {
  var failure = [Int](repeating: 0, count: needle.count)
  var matched = 0
  for index in 1 ..< max(needle.count, 1) {
    while matched > 0, needle[index] != needle[matched] { matched = failure[matched - 1] }
    if needle[index] == needle[matched] { matched += 1 }
    failure[index] = matched
  }
  matched = 0
  for (index, character) in haystack.enumerated() {
    while matched > 0, character != needle[matched] { matched = failure[matched - 1] }
    if character == needle[matched] { matched += 1 }
    if matched == needle.count { return index - needle.count + 1 }
  }
  return nil
}

/// Foundation's `AttributedString`, with the SwiftUI attribute scope (`kern`, `foregroundColor`, `font`, ...).
/// Expressible by a string literal, as on Apple platforms; `Text("key")` still takes the localized-key initializer because
/// `Text(_: AttributedString)` is a disfavored overload there too.
public struct AttributedString: Equatable, Sendable, _AttributeAccess, ExpressibleByStringLiteral, AttributedStringProtocol {
  /// A position between characters, as an offset from the start.
  public struct Index: Comparable, Hashable, Sendable {
    var offset: Int
    public static func < (left: AttributedString.Index, right: AttributedString.Index) -> Bool { left.offset < right.offset }
  }

  var _characters: [Character]
  var _attributes: [_TextAttributes]

  public init() { _characters = []; _attributes = [] }
  public init(stringLiteral value: String) { self.init(value) }
  public init(_ text: String) {
    _characters = Array(text)
    _attributes = Array(repeating: _TextAttributes(), count: _characters.count)
  }
  public init(_ text: String, attributes: AttributeContainer) {
    self.init(text)
    mergeAttributes(attributes)
  }
  public init(_ substring: AttributedSubstring) {
    self = substring._flattened
  }

  public var startIndex: AttributedString.Index { Index(offset: 0) }
  public var endIndex: AttributedString.Index { Index(offset: _characters.count) }
  public var _flattened: AttributedString { self }
  /// The plain text. (Foundation exposes a character view; the string is one.)
  public var characters: String { String(_characters) }

  /// A mutable slice proxy: attribute changes made through it are written
  /// back to this string. The text itself cannot be changed through a slice.
  public subscript(bounds: some RangeExpression<AttributedString.Index>) -> AttributedSubstring {
    get {
      let range = bounds.relative(to: _Positions(endIndex: endIndex))
      return AttributedSubstring(_base: self, _lower: range.lowerBound.offset, _upper: range.upperBound.offset)
    }
    set { self = newValue._base }
  }

  public mutating func append(_ s: some AttributedStringProtocol) {
    let other = s._flattened
    _characters.append(contentsOf: other._characters)
    _attributes.append(contentsOf: other._attributes)
  }
  public static func + (lhs: AttributedString, rhs: AttributedString) -> AttributedString {
    var result = lhs
    result.append(rhs)
    return result
  }
  public static func += (lhs: inout AttributedString, rhs: AttributedString) { lhs.append(rhs) }

  /// Merges `container` into every character.
  public mutating func mergeAttributes(_ container: AttributeContainer) {
    var index = 0
    while index < _attributes.count { _attributes[index]._merge(container._attributes); index += 1 }
  }
  public mutating func setAttributes(_ container: AttributeContainer) {
    var index = 0
    while index < _attributes.count { _attributes[index] = container._attributes; index += 1 }
  }

  /// The maximal runs of identically attributed text.
  public var runs: AttributedString.Runs {
    var result: [Runs.Run] = []
    var start = 0
    while start < _characters.count {
      var end = start + 1
      while end < _characters.count && _attributes[end] == _attributes[start] { end += 1 }
      result.append(Runs.Run(range: Index(offset: start)..<Index(offset: end), _attrs: _attributes[start]))
      start = end
    }
    return Runs(_runs: result)
  }

  /// Foundation's `AttributedString.Runs`: the runs in order, each with its range and attributes.
  public struct Runs: BidirectionalCollection, Sendable {
    public struct Index: Comparable, Hashable, Sendable {
      var offset: Int
      public static func < (lhs: AttributedString.Runs.Index, rhs: AttributedString.Runs.Index) -> Bool { lhs.offset < rhs.offset }
    }

    public struct Run: _AttributeAccess, Sendable {
      public let range: Range<AttributedString.Index>
      let _attrs: _TextAttributes
      public func _readAttributes() -> _TextAttributes { _attrs }
      public mutating func _modifyAttributes(_ body: (inout _TextAttributes) -> Void) {}
    }

    let _runs: [Run]
    public var startIndex: AttributedString.Runs.Index { Index(offset: 0) }
    public var endIndex: AttributedString.Runs.Index { Index(offset: _runs.count) }
    public func index(after i: AttributedString.Runs.Index) -> AttributedString.Runs.Index { Index(offset: i.offset + 1) }
    public func index(before i: AttributedString.Runs.Index) -> AttributedString.Runs.Index { Index(offset: i.offset - 1) }
    public subscript(position: AttributedString.Runs.Index) -> AttributedString.Runs.Run { _runs[position.offset] }
  }

  public func _readAttributes() -> _TextAttributes {
    guard var common = _attributes.first else { return _TextAttributes() }
    for value in _attributes { common = common._common(with: value) }
    return common
  }
  public mutating func _modifyAttributes(_ body: (inout _TextAttributes) -> Void) {
    var index = 0
    while index < _attributes.count { body(&_attributes[index]); index += 1 }
  }

  func _styledRuns() -> [_AttributedRun] {
    var result: [_AttributedRun] = []
    for run in runs {
      result.append(_AttributedRun(text: String(_characters[run.range.lowerBound.offset..<run.range.upperBound.offset]), attributes: run._attrs))
    }
    return result
  }
}

/// The positions of a string, so a `RangeExpression` of indices (`start...`, `..<end`) resolves against it.
private struct _Positions: Collection {
  let endIndex: AttributedString.Index
  var startIndex: AttributedString.Index { AttributedString.Index(offset: 0) }
  func index(after i: AttributedString.Index) -> AttributedString.Index { AttributedString.Index(offset: i.offset + 1) }
  subscript(position: AttributedString.Index) -> AttributedString.Index { position }
}

public struct AttributedSubstring: _AttributeAccess, AttributedStringProtocol {
  var _base: AttributedString
  let _lower: Int
  let _upper: Int

  public var startIndex: AttributedString.Index { .init(offset: _lower) }
  public var endIndex: AttributedString.Index { .init(offset: _upper) }
  public var characters: String { String(_base._characters[_lower..<_upper]) }
  public var _flattened: AttributedString {
    var result = AttributedString()
    result._characters = Array(_base._characters[_lower..<_upper])
    result._attributes = Array(_base._attributes[_lower..<_upper])
    return result
  }

  public func _readAttributes() -> _TextAttributes {
    guard _lower < _upper else { return _TextAttributes() }
    var common = _base._attributes[_lower]
    var index = _lower + 1
    while index < _upper { common = common._common(with: _base._attributes[index]); index += 1 }
    return common
  }
  public mutating func _modifyAttributes(_ body: (inout _TextAttributes) -> Void) {
    var index = _lower
    while index < _upper { body(&_base._attributes[index]); index += 1 }
  }
  public mutating func mergeAttributes(_ container: AttributeContainer) {
    _modifyAttributes { $0._merge(container._attributes) }
  }
  public mutating func setAttributes(_ container: AttributeContainer) {
    let value = container._attributes
    _modifyAttributes { $0 = value }
  }
}

/// Foundation's inline Markdown for `AttributedString(markdown:)`: emphasis, strong, code, strikethrough, links and
/// backslash escapes. Whitespace and line breaks are kept as written.
extension AttributedString {
  public struct MarkdownParsingOptions: Sendable {
    public enum FailurePolicy: Sendable { case throwError, returnPartiallyParsedIfPossible }
    public enum InterpretedSyntax: Sendable { case full, inlineOnly, inlineOnlyPreservingWhitespace }
    public var allowsExtendedAttributes = false
    public var interpretedSyntax = InterpretedSyntax.full
    public var failurePolicy = FailurePolicy.throwError
    public var languageCode: String?
    public init(
      allowsExtendedAttributes: Bool = false,
      interpretedSyntax: AttributedString.MarkdownParsingOptions.InterpretedSyntax = .full,
      failurePolicy: AttributedString.MarkdownParsingOptions.FailurePolicy = .throwError,
      languageCode: String? = nil
    ) {
      self.allowsExtendedAttributes = allowsExtendedAttributes
      self.interpretedSyntax = interpretedSyntax
      self.failurePolicy = failurePolicy
      self.languageCode = languageCode
    }
  }

  /// Links keep the text they are written with; `baseURL` is accepted for source compatibility.
  public init(markdown: String, options: AttributedString.MarkdownParsingOptions = .init(), baseURL: URL? = nil) throws {
    self.init()
    var parser = _InlineMarkdown(Array(markdown))
    parser.parse(into: &self, style: _InlineMarkdown.Style())
  }
}

struct _InlineMarkdown {
  struct Style {
    var bold = false, italic = false, code = false, strike = false
    var link: String?
  }

  let chars: [Character]
  var index = 0
  /// `labelEnd[i]` is where a link label scanned from `i` stops: at the `]` that closes it, or at the end of the input.
  /// It is decided once per position, right to left, from the positions after it. An opening bracket with no
  /// `](...)` after it therefore costs constant time, and no label is scanned twice. The rules are the ones the
  /// label scan applies (escapes, code, emphasis, strikethrough, and links nested in a label).
  let labelEnd: [Int]
  /// `nextParen[i]` is the first `)` at or after `i`, or the count of the input when there is none.
  let nextParen: [Int]

  init(_ chars: [Character]) {
    let count = chars.count
    var nextParen = [Int](repeating: count, count: count + 1)
    var position = count - 1
    while position >= 0 {
      nextParen[position] = chars[position] == ")" ? position : nextParen[position + 1]
      position -= 1
    }
    var labelEnd = [Int](repeating: count, count: count + 1)
    position = count - 1
    while position >= 0 {
      let char = chars[position]
      if char == "\\", position + 1 < count {
        labelEnd[position] = labelEnd[position + 2]
      } else if char == "]" {
        labelEnd[position] = position
      } else if char == "*" || char == "_" {
        let double = position + 1 < count && chars[position + 1] == char
        labelEnd[position] = labelEnd[double ? position + 2 : position + 1]
      } else if char == "~", position + 1 < count, chars[position + 1] == "~" {
        labelEnd[position] = labelEnd[position + 2]
      } else if char == "[" {
        let close = labelEnd[position + 1]
        labelEnd[position] = close
        if close + 1 < count, chars[close] == "]", chars[close + 1] == "(", nextParen[close + 2] < count {
          labelEnd[position] = labelEnd[nextParen[close + 2] + 1]
        }
      } else {
        labelEnd[position] = labelEnd[position + 1]
      }
      position -= 1
    }
    self.chars = chars
    self.labelEnd = labelEnd
    self.nextParen = nextParen
  }

  private func attributes(_ style: Style) -> AttributeContainer {
    var container = AttributeContainer()
    var css: _NodeValues = .init()
    if style.bold { css["font-weight"] = "700" }
    if style.italic { css["font-style"] = "italic" }
    if style.code { css["font-family"] = "ui-monospace, monospace" }
    if !css.isEmpty { container.font = Font(cssStyles: css) }
    if style.strike { container.strikethroughStyle = .single }
    if let link = style.link, let url = URL(string: link) { container.link = url }
    // Recorded beside the styling above: Foundation's runs carry these intents, and a reader that draws its own
    // fonts from them (`run.inlinePresentationIntent`) gets the same emphasis the parser wrote.
    var intent: InlinePresentationIntent = []
    if style.italic { intent.insert(.emphasized) }
    if style.bold { intent.insert(.stronglyEmphasized) }
    if style.code { intent.insert(.code) }
    if style.strike { intent.insert(.strikethrough) }
    if !intent.isEmpty { container.inlinePresentationIntent = intent }
    return container
  }

  private mutating func flush(_ text: inout String, into result: inout AttributedString, _ style: Style) {
    guard !text.isEmpty else { return }
    result.append(AttributedString(text, attributes: attributes(style)))
    text = ""
  }

  /// The input, or the label of a link. A label has its own style and pending text, and closes at the `]` that ends
  /// it; `resume` is where the enclosing scope continues, after the link's `)`.
  private struct Scope {
    var style: Style
    let resume: Int
    var text = ""
  }

  private mutating func flushTop(_ scopes: inout [Scope], into result: inout AttributedString) {
    let top = scopes.count - 1
    let style = scopes[top].style
    flush(&scopes[top].text, into: &result, style)
  }

  /// Parses the whole input. Link labels are scopes on an explicit stack instead of nested calls, so nesting depth
  /// costs heap memory rather than call stack, and the output is the same as the recursive form.
  mutating func parse(into result: inout AttributedString, style: Style) {
    var scopes = [Scope(style: style, resume: chars.count)]
    while true {
      let top = scopes.count - 1
      if index >= chars.count {
        flushTop(&scopes, into: &result)
        if top == 0 { return }
        index = scopes[top].resume
        scopes.removeLast()
        continue
      }
      let char = chars[index]
      if char == "\\", index + 1 < chars.count {
        scopes[top].text.append(chars[index + 1]); index += 2
      } else if top > 0 && char == "]" {
        flushTop(&scopes, into: &result)
        index = scopes[top].resume
        scopes.removeLast()
      } else if char == "`" {
        flushTop(&scopes, into: &result); scopes[top].style.code.toggle(); index += 1
      } else if char == "*" || char == "_" {
        let double = index + 1 < chars.count && chars[index + 1] == char
        flushTop(&scopes, into: &result)
        if double { scopes[top].style.bold.toggle(); index += 2 } else { scopes[top].style.italic.toggle(); index += 1 }
      } else if char == "~", index + 1 < chars.count, chars[index + 1] == "~" {
        flushTop(&scopes, into: &result); scopes[top].style.strike.toggle(); index += 2
      } else if char == "[" {
        let start = index
        let close = labelEnd[start + 1]
        if close + 1 < chars.count, chars[close] == "]", chars[close + 1] == "(",
           nextParen[close + 2] < chars.count {
          let end = nextParen[close + 2]
          flushTop(&scopes, into: &result)
          var linkStyle = scopes[top].style
          linkStyle.link = String(chars[(close + 2)..<end])
          scopes.append(Scope(style: linkStyle, resume: end + 1))
          index = start + 1
        } else {
          scopes[top].text.append("["); index = start + 1
        }
      } else {
        scopes[top].text.append(char); index += 1
      }
    }
  }
}

extension Text {
  /// Renders the string's attribute runs as styled inline spans. Disfavored, as in SwiftUI, so a string literal is a key.
  @_disfavoredOverload public init(_ attributedContent: AttributedString) {
    self.init(_attributedRuns: attributedContent._styledRuns())
  }
}

// Foundation declares these on StringProtocol.
extension StringProtocol {
  public var localizedLowercase: String { lowercased() }
  public var localizedUppercase: String { uppercased() }
  public var localizedCapitalized: String {
    var result = ""
    var startsWord = true
    for character in self {
      let piece = String(character)
      result += startsWord ? piece.uppercased() : piece.lowercased()
      startsWord = character == " " || character == "\n" || character == "\t" || character == "-"
    }
    return result
  }
}

