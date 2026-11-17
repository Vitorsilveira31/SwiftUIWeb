// SwiftUI's localization spelling for every host: `LocalizedStringKey`,
// `Text("key")`, `String(localized:)`. Translations come from string catalogs
// (`.xcstrings`) or `.strings` files compiled by `Tools/compile-strings.mjs`
// into a table registered at launch; natively Xcode and Foundation do the same
// job, so application code is written once.

/// One argument interpolated into a localized string.
@_spi(Renderer) import SwiftUIWebTransferable
public enum _LocalizedStringArgument: Hashable, Sendable {
  case string(String)
  case integer(Int)
  case floating(Double)

  var text: String {
    switch self {
    case .string(let value): return value
    case .integer(let value): return String(value)
    case .floating(let value): return "\(value)"
    }
  }
}

/// SwiftUI's number interpolation hook: the printf specifier a number interpolated into a
/// `LocalizedStringKey` contributes to the key, and the argument it is substituted with.
public protocol _FormatSpecifiable: Equatable, CustomStringConvertible {
  var _specifier: String { get }
  var _localizedStringArgument: _LocalizedStringArgument { get }
}

public protocol _IntegerFormatSpecifiable: _FormatSpecifiable, BinaryInteger {}
public extension _IntegerFormatSpecifiable {
  var _localizedStringArgument: _LocalizedStringArgument {
    if let value = Int(exactly: self) { return .integer(value) }
    return .string(description)
  }
}

extension Int: _IntegerFormatSpecifiable { public var _specifier: String { "%lld" } }
extension Int8: _IntegerFormatSpecifiable { public var _specifier: String { "%d" } }
extension Int16: _IntegerFormatSpecifiable { public var _specifier: String { "%d" } }
extension Int32: _IntegerFormatSpecifiable { public var _specifier: String { "%d" } }
extension Int64: _IntegerFormatSpecifiable { public var _specifier: String { "%lld" } }
extension UInt: _IntegerFormatSpecifiable { public var _specifier: String { "%llu" } }
extension UInt8: _IntegerFormatSpecifiable { public var _specifier: String { "%u" } }
extension UInt16: _IntegerFormatSpecifiable { public var _specifier: String { "%u" } }
extension UInt32: _IntegerFormatSpecifiable { public var _specifier: String { "%u" } }
extension UInt64: _IntegerFormatSpecifiable { public var _specifier: String { "%llu" } }
extension Double: _FormatSpecifiable {
  public var _specifier: String { "%lf" }
  public var _localizedStringArgument: _LocalizedStringArgument { .floating(self) }
}
extension Float: _FormatSpecifiable {
  public var _specifier: String { "%f" }
  public var _localizedStringArgument: _LocalizedStringArgument { .floating(Double(self)) }
}

/// The key of a localized string. A literal is the key itself; an
/// interpolation becomes a format key (`"%lld works"`) plus its arguments, the
/// same shape Xcode extracts into a string catalog.
/// A string from data without the object-replacement characters that mark an interpolated `Image`: a comment that
/// carries "\u{FFFC}https://elsewhere/p.gif\u{FFFC}" must not become an image in another reader's text.
func _withoutImageMarkers(_ value: String) -> String {
  value.contains("\u{FFFC}") ? String(value.unicodeScalars.filter { $0 != "\u{FFFC}" }.map(Character.init)) : value
}

public struct LocalizedStringKey: Hashable, Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
  package var key: String
  package var arguments: [_LocalizedStringArgument]

  public init(_ value: String) { key = _withoutImageMarkers(value); arguments = [] }
  package init(key: String, arguments: [_LocalizedStringArgument]) { self.key = key; self.arguments = arguments }
  public init(stringLiteral value: String) { key = value; arguments = [] }
  public init(stringInterpolation: LocalizedStringKey.StringInterpolation) {
    key = stringInterpolation.key
    arguments = stringInterpolation.arguments
  }

  public struct StringInterpolation: StringInterpolationProtocol {
    var key = ""
    var arguments: [_LocalizedStringArgument] = []

    public init(literalCapacity: Int, interpolationCount: Int) {}
    public mutating func appendLiteral(_ literal: String) {
      for character in literal { key.append(character); if character == "%" { key.append("%") } }
    }
    public mutating func appendInterpolation(_ value: String) { key += "%@"; arguments.append(.string(_withoutImageMarkers(value))) }
    /// A number keeps its printf specifier in the key (`%lld` for `Int`, `%lf` for `Double`), as Xcode extracts it.
    public mutating func appendInterpolation<T>(_ value: T) where T: _FormatSpecifiable {
      key += value._specifier; arguments.append(value._localizedStringArgument)
    }
    public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T) {
      key += "%@"; arguments.append(.string(_withoutImageMarkers(value.description)))
    }
    @_spi(Renderer) public mutating func _appendString(_ value: String) { key += "%@"; arguments.append(.string(_withoutImageMarkers(value))) }
    /// `Text("\(Image(systemName: "star")) starred")`: the image is set in the line. The argument carries the image
    /// between object-replacement characters, which `Text` turns back into an inline run.
    public mutating func appendInterpolation(_ image: Image) {
      // The name loses any U+FFFC of its own: it would end the marker early and start another (with a forged mark).
      let name = String(image.source.unicodeScalars.filter { $0 != "\u{FFFC}" }.map(Character.init))
      Text._installInlineImageSplitting()
      key += "%@"; arguments.append(.string("\u{FFFC}" + _ImageAssets.marked(name, allowsRemote: image.allowsRemoteSource) + "\u{FFFC}"))
    }
    /// `\(count, specifier: "%02d")`: the format specifier stays in the key, as Xcode extracts it.
    public mutating func appendInterpolation<T: BinaryInteger>(_ value: T, specifier: String) {
      key += specifier; arguments.append(.integer(Int(truncatingIfNeeded: value)))
    }
    public mutating func appendInterpolation<T: BinaryFloatingPoint>(_ value: T, specifier: String) {
      key += specifier; arguments.append(.floating(Double(value)))
    }
  }

  /// The text for the active language, with arguments substituted.
  package var resolved: String { LocalizationTable.resolve(self) }
}

/// A translated value: one string, or the plural forms of the first integer
/// argument (`zero`, `one`, `two`, `few`, `many`, `other`).
package enum LocalizedValue: Hashable, Sendable {
  case text(String)
  case plural([String: String])
}

/// The registered translations and the language used to pick among them.
///
/// Generated translation tables (`Tools/compile-strings.mjs`) call the `Generated` SPI from consumer packages.
@_spi(Generated) public enum LocalizationTable {
  private static let lock = _RuntimeLock()
  private final class State: @unchecked Sendable {
    var tables: [String: [String: LocalizedValue]] = .init()
    var sortedTables: [String: [LocalizationSortedEntries]] = .init()
    var development = "en"
    var preferred: String?
    /// What `lookup` found for a key in the preferred language (nil: nothing), with the key exactly as it was looked up:
    /// a render resolves the same keys on every pass, and each lookup otherwise rebuilt the candidate language names and
    /// searched every table. A `String` key matches any canonically equivalent one, where the tables compare bytes, so
    /// a hit counts only when the bytes are the same too. Emptied whenever a table or a language changes.
    var found = _ReferenceTable<(key: String, result: (value: LocalizedValue, language: String)?)>()
  }
  // Every access happens under `lock`.
  private static let state = State()
  private static var tables: [String: [String: LocalizedValue]] {
    get { state.tables }
    _modify { yield &state.tables }
  }
  private static var sortedTables: [String: [LocalizationSortedEntries]] {
    get { state.sortedTables }
    _modify { yield &state.sortedTables }
  }
  private static var development: String {
    get { state.development }
    set { state.development = newValue; forgetLookups() }
  }
  private static var preferred: String? {
    get { state.preferred }
    set { state.preferred = newValue; forgetLookups() }
  }
  /// The cached lookups stop holding (`State.found`). Under `lock`.
  private static func forgetLookups() {
    state.found.removeAll(keepingCapacity: true)
  }
  private static let lookupCacheLimit = 4096

  /// The language whose entries answer when the preferred one lacks a key.
  @_spi(Generated) public static var developmentLanguage: String {
    get { lock.withLock { development } }
    set { lock.withLock { development = newValue } }
  }
  /// The language to show, as a BCP 47 or POSIX identifier (`pt-BR`, `pt_BR`).
  /// `nil` selects the development language.
  package static var preferredLanguage: String? {
    get { lock.withLock { preferred } }
    set { lock.withLock { preferred = newValue } }
  }

  package static func register(language: String, entries: [String: LocalizedValue]) {
    let name = normalized(language)
    lock.withLock {
      var merged = tables[name] ?? .init()
      for (key, value) in entries { merged[key] = value }
      tables[name] = merged
      forgetLookups()
    }
  }

  /// Registers a blob of entries sorted by the UTF-8 bytes of the key (what
  /// `Tools/compile-strings.mjs` emits). It stays in the binary's data section and
  /// is searched in place, with no `Dictionary` built;
  /// `register(language:entries:)` values take precedence.
  @_spi(Generated) public static func register(language: String, sorted blob: StaticString) {
    let name = normalized(language)
    let entries = LocalizationSortedEntries(blob)
    lock.withLock { sortedTables[name, default: []].append(entries); forgetLookups() }
  }

  package static func removeAll() { lock.withLock { tables = .init(); sortedTables = .init(); forgetLookups() } }

  static func normalized(_ identifier: String) -> String {
    var result = ""
    for character in identifier { result.append(character == "_" ? "-" : character) }
    return result
  }

  private static func baseLanguage(of identifier: String) -> String {
    var result = ""
    for character in identifier { if character == "-" { break }; result.append(character) }
    return result
  }

  private static func lookup(_ key: String, language requested: String? = nil) -> (value: LocalizedValue, language: String)? {
    lock.withLock {
      guard requested == nil else { return search(key, language: requested) }
      if let hit = state.found[key] {
        if hit.key.utf8.elementsEqual(key.utf8) { return hit.result }
        return search(key, language: nil)
      }
      if state.found.count >= lookupCacheLimit { forgetLookups() }
      let result = search(key, language: nil)
      state.found[key] = (key, result)
      return result
    }
  }

  /// The value of `key` in the first language that has it: the requested or preferred one, its base language, then the
  /// development language and its base. Under `lock`.
  private static func search(_ key: String, language requested: String?) -> (value: LocalizedValue, language: String)? {
    var candidates: [String] = []
    if let preferred = requested ?? preferred {
      let name = normalized(preferred)
      candidates.append(name)
      candidates.append(baseLanguage(of: name))
    }
    let source = normalized(development)
    candidates.append(source)
    candidates.append(baseLanguage(of: source))
    for language in candidates {
      if let value = tables[language]?[key] { return (value, language) }
      for entries in (sortedTables[language] ?? []).reversed() {
        if let value = entries.value(for: key) { return (value, language) }
      }
    }
    return nil
  }

  package static func resolve(_ key: LocalizedStringKey, language: String? = nil) -> String {
    guard let found = lookup(key.key, language: language) else { return format(key.key, key.arguments, language: developmentLanguage, escaped: !key.arguments.isEmpty) }
    switch found.value {
    case .text(let text):
      return key.arguments.isEmpty ? text : format(text, key.arguments, language: found.language, escaped: true)
    case .plural(let forms):
      var count = 0
      for argument in key.arguments { if case .integer(let value) = argument { count = value; break } }
      let category = count == 0 && forms["zero"] != nil ? "zero" : pluralCategory(language: found.language, count: count)
      let template = forms[category] ?? forms["other"] ?? key.key
      return format(template, key.arguments, language: found.language, escaped: true)
    }
  }

  /// CLDR cardinal plural category for the languages the studio ships; the
  /// categories other languages need can be added here.
  static func pluralCategory(language: String, count: Int) -> String {
    let base = baseLanguage(of: language)
    let magnitude = count.magnitude
    switch base {
    case "ja", "zh", "ko", "vi", "th", "id": return "other"
    case "pt": return language == "pt-PT" ? (magnitude == 1 ? "one" : "other") : (magnitude <= 1 ? "one" : "other")
    case "fr": return magnitude <= 1 ? "one" : "other"
    default: return magnitude == 1 ? "one" : "other"
    }
  }

  /// Substitutes `%@`, `%lld`, `%d`, `%lf`, `%f` and positional `%2$@` forms.
  static func format(_ template: String, _ arguments: [_LocalizedStringArgument], language: String, escaped: Bool) -> String {
    guard escaped else { return template }
    let characters = Array(template)
    var result = ""
    var next = 0
    var index = 0
    while index < characters.count {
      let character = characters[index]
      guard character == "%", index + 1 < characters.count else { result.append(character); index += 1; continue }
      if characters[index + 1] == "%" { result.append("%"); index += 2; continue }
      var cursor = index + 1
      var position: Int?
      var digits = 0
      var scan = cursor
      while scan < characters.count, let digit = characters[scan]._asciiDigitValue { digits = min(digits * 10 + digit, _formatFieldLimit); scan += 1 }
      if scan > cursor, scan < characters.count, characters[scan] == "$" { position = digits - 1; cursor = scan + 1 }
      while cursor < characters.count, characters[cursor] == "l" || characters[cursor] == "." || characters[cursor]._asciiDigitValue != nil { cursor += 1 }
      guard cursor < characters.count else { result.append(character); index += 1; continue }
      let specifier = characters[cursor]
      guard specifier == "@" || specifier == "d" || specifier == "i" || specifier == "f" || specifier == "s" || specifier == "u" else {
        result.append(character); index += 1; continue
      }
      let argumentIndex = position ?? next
      if position == nil { next += 1 }
      if argumentIndex >= 0, argumentIndex < arguments.count {
        let flags = String(characters[(position == nil ? index + 1 : scan + 1) ..< cursor]).filter { $0 != "l" }
        result += _padded(arguments[argumentIndex], specifier: specifier, flags: flags)
      }
      index = cursor + 1
    }
    return result
  }
}

/// Applies the width, zero flag and precision of a printf-style specifier (`%02d`, `%5.1f`, `%.2f`).
/// The largest width, precision or argument position a translation may ask for: a template comes from a catalog, and
/// `%2147483647d` would ask for two gigabytes of padding.
private let _formatFieldLimit = 100_000
private func _boundedField(_ digits: String) -> Int { digits.isEmpty ? 0 : min(Int(digits.prefix(7)) ?? 0, _formatFieldLimit) }

private func _padded(_ argument: _LocalizedStringArgument, specifier: Character, flags: String) -> String {
  var zero = false
  var width = 0
  var precision: Int?
  var seenDot = false
  var digits = ""
  for (offset, character) in flags.enumerated() {
    if character == "." {
      width = _boundedField(digits)
      digits = ""
      seenDot = true
    } else if let digit = character._asciiDigitValue {
      if offset == 0, digit == 0 { zero = true } else { digits.append(character) }
    }
  }
  if seenDot { precision = _boundedField(digits) } else { width = _boundedField(digits) }
  var text = argument.text
  if specifier == "f", let precision {
    switch argument {
    case .floating(let value): text = _fixed(value, precision)
    case .integer(let value): text = _fixed(Double(value), precision)
    case .string: break
    }
  }
  guard text.count < width else { return text }
  let fill = String(repeating: zero && specifier != "@" && specifier != "s" ? "0" : " ", count: width - text.count)
  if zero, text.first == "-" { return "-" + fill + text.dropFirst() }
  return fill + text
}

/// `%.Nf` of a number interpolated into `Text`: the digits of the double's exact value, rounded half to even, as
/// Foundation's `String(format:)` writes them (`%.2f` of 1e20 is every digit, `%.20f` of 0.1 is 0.10000000000000000555).
private func _fixed(_ value: Double, _ precision: Int) -> String {
  guard value.isFinite else { return "\(value)" }
  // The sign of the value itself, as C and Foundation write it: %.2f of -0.001 (and of -0.0) is "-0.00".
  return (value.sign == .minus ? "-" : "") + _fixedBody(abs(value), max(0, precision), false)
}
