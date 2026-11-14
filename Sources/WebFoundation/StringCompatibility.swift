@_spi(Renderer) import SwiftUIWebTransferable

enum WebStringComponents {
  /// The units Foundation compares a string by: its characters, compared with canonical equivalence ("e\u{301}" equals
  /// "é"), except that "\r\n" is two units, as NSString reads it, so "\n" is found inside it. (A Character comparison alone
  /// would never see the "\n"; a scalar one would miss canonically equivalent text.)
  static func foundationUnits(_ value: String) -> [Character] {
    var units: [Character] = []
    units.reserveCapacity(value.utf8.count)
    for character in value {
      if character == "\r\n" {
        units.append("\r")
        units.append("\n")
      } else {
        units.append(character)
      }
    }
    return units
  }

  /// The offsets in `units` where `target` starts, left to right without overlap.
  static func occurrences(of target: [Character], in units: [Character]) -> [Int] {
    guard let first = target.first, target.count <= units.count else { return [] }
    var found: [Int] = []
    var index = 0
    while index + target.count <= units.count {
      if units[index] == first, units[index ..< index + target.count].elementsEqual(target) {
        found.append(index)
        index += target.count
      } else {
        index += 1
      }
    }
    return found
  }

  /// Split at every occurrence of `separator`, as Foundation splits (see `foundationUnits`): "a\r\nb" split at "\n" is
  /// ["a\r", "b"], and "cafe\u{301}" split at "é" is ["caf", ""].
  static func split(_ value: String, separatedBy separator: String) -> [String] {
    guard !separator.isEmpty else { return [value] }
    // Without a "\r" the units are the characters themselves: the string is scanned in place.
    if !value.utf8.contains(13), !separator.utf8.contains(13) {
      var result: [String] = []
      var segmentStart = value.startIndex, cursor = value.startIndex
      let first = separator.first!
      while cursor < value.endIndex {
        if value[cursor] == first, value[cursor...].hasPrefix(separator) {
          result.append(String(value[segmentStart ..< cursor]))
          cursor = value.index(cursor, offsetBy: separator.count)
          segmentStart = cursor
        } else {
          cursor = value.index(after: cursor)
        }
      }
      result.append(String(value[segmentStart...]))
      return result
    }
    let units = foundationUnits(value), target = foundationUnits(separator)
    var result: [String] = []
    var segmentStart = 0
    for start in occurrences(of: target, in: units) {
      result.append(String(units[segmentStart ..< start]))
      segmentStart = start + target.count
    }
    result.append(String(units[segmentStart...]))
    return result
  }

  static func split(_ value: String, where isSeparator: (Character) -> Bool) -> [String] {
    var result: [String] = []
    var segmentStart = value.startIndex
    var cursor = value.startIndex
    while cursor < value.endIndex {
      let next = value.index(after: cursor)
      if isSeparator(value[cursor]) {
        result.append(String(value[segmentStart..<cursor]))
        segmentStart = next
      }
      cursor = next
    }
    result.append(String(value[segmentStart..<value.endIndex]))
    return result
  }
}

// Keep this target Foundation-free. Embedded Swift can report Foundation as
// importable even when its String compatibility APIs are absent.
/// Minimal CharacterSet surface used by the Foundation-compatible String APIs.
public struct CharacterSet: Sendable {
  fileprivate let isWhitespace: @Sendable (Character) -> Bool

  fileprivate init(isWhitespace: @escaping @Sendable (Character) -> Bool) {
    self.isWhitespace = isWhitespace
  }

  // Unicode's white space, as Foundation's sets: a no-break space, U+2028 or "\r\n" (one Character) are white space too.
  public static let whitespacesAndNewlines = CharacterSet { $0.isWhitespace }
  public static let whitespaces = CharacterSet { $0.isWhitespace && !$0.isNewline }
  public static let newlines = CharacterSet { $0.isNewline }
  public static let letters = CharacterSet { $0.isLetter }
  public static let uppercaseLetters = CharacterSet { $0.isUppercase }
  public static let lowercaseLetters = CharacterSet { $0.isLowercase }
  public static let decimalDigits = CharacterSet { $0.isWholeNumber }
  public static let alphanumerics = CharacterSet { $0.isLetter || $0.isNumber }
  public static let punctuationCharacters = CharacterSet { $0.isPunctuation }
  public static let symbols = CharacterSet { $0.isSymbol }
  // RFC 3986 groupings used for percent-encoding (the characters that may stay literal).
  public static let urlQueryAllowed = CharacterSet { $0.isASCII && ($0.isLetter || $0.isNumber || "-._~!$&'()*+,;=:@/?".contains($0)) }
  public static let urlPathAllowed = CharacterSet { $0.isASCII && ($0.isLetter || $0.isNumber || "-._~!$&'()*+,;=:@/".contains($0)) }
  public static let urlHostAllowed = CharacterSet { $0.isASCII && ($0.isLetter || $0.isNumber || "-._~!$&'()*+,;=:[]".contains($0)) }
  public static let urlFragmentAllowed = urlQueryAllowed

  fileprivate func contains(_ character: Character) -> Bool { isWhitespace(character) }

  public init(charactersIn string: String) {
    let members = Array(string.unicodeScalars)
    self.init { character in character.unicodeScalars.allSatisfy { members.contains($0) } }
  }

  /// Foundation-compatible membership test used by `onKeyPress(characters:)`.
  public func contains(_ member: Unicode.Scalar) -> Bool { isWhitespace(Character(member)) }
}

extension String {
  public func components(separatedBy separator: String) -> [String] {
    WebStringComponents.split(self, separatedBy: separator)
  }

  public func components(separatedBy separator: CharacterSet) -> [String] {
    WebStringComponents.split(self, where: separator.isWhitespace)
  }
}

extension String {
  public enum Encoding: Sendable { case utf8, ascii, unicode, utf16, isoLatin1 }
  public init?(data: Data, encoding: Encoding) {
    self = String(decoding: data.toArray(), as: UTF8.self)
  }
  public func data(using encoding: Encoding, allowLossyConversion: Bool = false) -> Data? { Data(utf8) }

  public func addingPercentEncoding(withAllowedCharacters allowed: CharacterSet) -> String? {
    let hex = Array("0123456789ABCDEF")
    var out = ""
    for character in self {
      if allowed.contains(character) { out.append(character); continue }
      for byte in String(character).utf8 {
        out.append("%"); out.append(hex[Int(byte >> 4)]); out.append(hex[Int(byte & 15)])
      }
    }
    return out
  }

  public var removingPercentEncoding: String? {
    guard contains("%") else { return self }
    var bytes: [UInt8] = []
    let source = Array(utf8)
    var index = 0
    func digit(_ byte: UInt8) -> UInt8? {
      switch byte {
      case 48...57: return byte - 48
      case 65...70: return byte - 55
      case 97...102: return byte - 87
      default: return nil
      }
    }
    while index < source.count {
      if source[index] == 37 {
        guard index + 2 < source.count, let high = digit(source[index + 1]), let low = digit(source[index + 2]) else { return nil }
        bytes.append(high << 4 | low)
        index += 3
      } else {
        bytes.append(source[index])
        index += 1
      }
    }
    // Foundation answers nil for bytes that are not UTF-8 ("%FF", the overlong "%C0%AF"), rather than a repaired string a
    // validator would then accept.
    return String(validating: bytes, as: UTF8.self)
  }
}

// Foundation declares these on StringProtocol, so a Substring (`line[colon...]`) has them too.
extension StringProtocol {
  public func replacingOccurrences(of target: String, with replacement: String) -> String {
    String(self).replacingOccurrences(of: target, with: replacement)
  }

  public func trimmingCharacters(in set: CharacterSet) -> String {
    String(self).trimmingCharacters(in: set)
  }

  public func components(separatedBy separator: String) -> [String] {
    String(self).components(separatedBy: separator)
  }

  public func components(separatedBy separator: CharacterSet) -> [String] {
    String(self).components(separatedBy: separator)
  }

  /// Foundation's `range(of:options:range:locale:)`: the first (or, with `.backwards`, the last) range equal to
  /// `aString` within `searchRange`. `.caseInsensitive` compares lowercased characters and `.anchored` only accepts a
  /// match at the start (or, backwards, the end) of the search range.
  public func range<T: StringProtocol>(
    of aString: T,
    options mask: String.CompareOptions = [],
    range searchRange: Range<Index>? = nil,
    locale: Locale? = nil
  ) -> Range<Index>? {
    let needle = Array(aString)
    guard !needle.isEmpty else { return nil }
    let bounds = searchRange ?? startIndex..<endIndex
    let caseless = mask.contains(.caseInsensitive)
    func same(_ lhs: Character, _ rhs: Character) -> Bool { caseless ? lhs.lowercased() == rhs.lowercased() : lhs == rhs }
    func match(at start: Index) -> Index? {
      var position = start
      for character in needle {
        guard position < bounds.upperBound, same(self[position], character) else { return nil }
        position = index(after: position)
      }
      return position
    }
    if mask.contains(.backwards) {
      var start = bounds.upperBound
      if mask.contains(.anchored) {
        for _ in needle {
          guard start > bounds.lowerBound else { return nil }
          start = index(before: start)
        }
        return match(at: start).flatMap { $0 == bounds.upperBound ? start..<$0 : nil }
      }
      while start > bounds.lowerBound {
        start = index(before: start)
        if let end = match(at: start) { return start..<end }
      }
      return nil
    }
    if mask.contains(.anchored) { return match(at: bounds.lowerBound).map { bounds.lowerBound..<$0 } }
    var start = bounds.lowerBound
    while start < bounds.upperBound {
      if let end = match(at: start) { return start..<end }
      start = index(after: start)
    }
    return nil
  }
}

public extension String {
  func trimmingCharacters(in set: CharacterSet) -> String {
    var start = startIndex
    while start < endIndex && set.isWhitespace(self[start]) {
      start = index(after: start)
    }
    var end = endIndex
    while end > start {
      let previous = index(before: end)
      if !set.isWhitespace(self[previous]) { break }
      end = previous
    }
    return String(self[start..<end])
  }

  func contains(_ other: String) -> Bool {
    guard !other.isEmpty else { return true }
    var index = startIndex
    while index < endIndex {
      if self[index...].hasPrefix(other) { return true }
      index = self.index(after: index)
    }
    return false
  }

  /// Foundation's form: each word's first letter uppercased and the rest lowercased (`"hELLO wORLD"` is `"Hello World"`).
  var capitalized: String {
    split(separator: " ", omittingEmptySubsequences: false).map { word in
      guard let first = word.first else { return "" }
      return String(first).uppercased() + word.dropFirst().lowercased()
    }.joined(separator: " ")
  }

  /// One pass over the string, matched as Foundation matches (`WebStringComponents.foundationUnits`): canonically
  /// equivalent text is found, and so is "\n" inside "\r\n".
  func replacingOccurrences(of target: String, with replacement: String) -> String {
    guard let first = target.first else { return self }
    // Without a "\r" the units are the characters themselves: the string is scanned in place, nothing copied up front.
    if !utf8.contains(13), !target.utf8.contains(13) {
      var result = ""
      var cursor = startIndex, copiedUpTo = startIndex
      while cursor < endIndex {
        if self[cursor] == first, self[cursor...].hasPrefix(target) {
          result += self[copiedUpTo ..< cursor]
          result += replacement
          cursor = index(cursor, offsetBy: target.count)
          copiedUpTo = cursor
        } else {
          cursor = index(after: cursor)
        }
      }
      return copiedUpTo == startIndex ? self : result + self[copiedUpTo...]
    }
    let units = WebStringComponents.foundationUnits(self)
    let needle = WebStringComponents.foundationUnits(target)
    let starts = WebStringComponents.occurrences(of: needle, in: units)
    guard !starts.isEmpty else { return self }
    var result = ""
    var copied = 0
    for start in starts {
      result += String(units[copied ..< start])
      result += replacement
      copied = start + needle.count
    }
    return result + String(units[copied...])
  }
}
