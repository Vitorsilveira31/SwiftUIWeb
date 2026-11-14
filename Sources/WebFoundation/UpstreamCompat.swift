// Foundation surface that larger shared applications reach for (URL parts, NSLocalizedString, DateFormatter,
// RelativeDateTimeFormatter, Duration formatting). Browser builds only; native builds use the real Foundation.
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebInternationalization

/// Foundation's root class; the application classes that name it as a base only need it to exist.
open class NSObject {
  public init() {}
  /// Foundation's `isEqual(_:)` (NSObject is declared in ObjectiveC, which the parity graphs do not compare): identity, unless a subclass compares its contents.
  package func isEqual(_ object: Any?) -> Bool { (object as? NSObject) === self }
  /// Apple's `hash`: derived from identity, unless a subclass hashes the value it compares.
  package var hash: Int { ObjectIdentifier(self).hashValue }
  /// Key-value coding's entry point (`NSObject.value(forKey:)`, declared in Foundation). Predicates read class
  /// instances through it, so a class that wants to be filtered by key overrides it and answers its properties by
  /// name. Foundation reaches Objective-C properties by reflection and raises for an undefined key; the default
  /// here has no properties and answers nil.
  open func value(forKey key: String) -> Any? { nil }
  /// The bytes `NSKeyedArchiver` writes for this object. A class that can be archived overrides this; Foundation
  /// rejects an object that is not NSCoding the same way (`NSCocoaError` 4866, `NSCoderInvalidValueError`).
  @_spi(KeyedArchiving) open func _keyedArchiveBytes() throws -> Data { throw _KeyedArchiveError.notArchivable }
}

/// The error `NSKeyedArchiver` throws for an object that cannot be archived.
enum _KeyedArchiveError: Error {
  case notArchivable
}

/// Foundation's box for a value of a C type. The browser build keeps the words a typed initializer wrote (AVFoundation's
/// `NSValue(time:)` is one); the byte-level initializers and `getValue` are not part of it.
open class NSValue: NSObject {
  /// What the typed initializers store, as 64-bit words.
  package let _words: [Int64]
  package init(_words: [Int64]) { self._words = _words; super.init() }
  public override init() { _words = []; super.init() }
  package override func isEqual(_ object: Any?) -> Bool { (object as? NSValue)?._words == _words }
  package override var hash: Int { _words.reduce(0) { $0 &* 31 &+ $1.hashValue } }
}

/// Foundation's JSON `null`: what `JSONSerialization` returns for a null value, and what a value must be to be written as one.
open class NSNull: NSObject {}

/// `NSMutableData` for code that builds a request body and converts it with `as Data`
/// (the source lowering rewrites that cast to `Data(_:)`).
public final class NSMutableData {
  private(set) var data = Data()
  public init() {}
  public func append(_ other: Data) { data.append(contentsOf: other) }
  public var length: Int { data.count }
}

extension Data {
  /// The bridge `x as Data` lowers to for an `NSMutableData` (`Data(_bridging:)`, see the lowering's `as-data-bridge`).
  @_spi(Renderer) public init(_bridging mutable: NSMutableData) { self = mutable.data }
}

/// The key itself: localization in the browser goes through `Text` and the String Catalog resources.
public func NSLocalizedString(_ key: String, tableName: String? = nil, bundle: Bundle = .main, value: String = "", comment: String) -> String {
  value.isEmpty ? key : value
}

extension URL {
  /// The scheme, host, port and path as the browser's fetch parser reads them (see `_EmbeddedURLParts`). A string the
  /// browser rejects has none of them, rather than a component read from the wrong place.
  public var scheme: String? { _EmbeddedURLParts.parse(absoluteString)?.scheme }
  public var host: String? { _EmbeddedURLParts.parse(absoluteString)?.host }
  public func host(percentEncoded: Bool = true) -> String? { host }
  public var port: Int? { _EmbeddedURLParts.parse(absoluteString)?.port }
  /// The path with its `%XX` escapes decoded, as Foundation's `path`; `path(percentEncoded: true)` keeps them.
  public var path: String { path(percentEncoded: false) }
  public func path(percentEncoded: Bool = true) -> String {
    let raw = _EmbeddedURLParts.parse(absoluteString)?.path ?? ""
    return percentEncoded ? raw : raw.removingPercentEncoding ?? raw
  }
  public var query: String? {
    // A "?" inside the fragment does not start a query: "https://a/#x?next=evil" has none, as Foundation answers.
    guard let mark = absoluteString.firstIndex(of: "?") else { return nil }
    if let hash = absoluteString.firstIndex(of: "#"), hash < mark { return nil }
    var text = absoluteString[absoluteString.index(after: mark)...]
    if let hash = text.firstIndex(of: "#") { text = text[..<hash] }
    return String(text)
  }
  public var fragment: String? {
    guard let hash = absoluteString.firstIndex(of: "#") else { return nil }
    return String(absoluteString[absoluteString.index(after: hash)...])
  }
  public var relativeString: String { absoluteString }
  public var absoluteURL: URL { self }
  public var isFileURL: Bool { scheme == "file" }
  public var lastPathComponent: String {
    var components = path.split(separator: "/", omittingEmptySubsequences: true)
    guard let last = components.popLast() else { return path == "/" ? "/" : "" }
    return String(last)
  }
  public var pathExtension: String {
    let name = lastPathComponent
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
    return String(name[name.index(after: dot)...])
  }
  public var pathComponents: [String] {
    let text = path
    var parts = text.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    if text.hasPrefix("/") { parts.insert("/", at: 0) }
    return parts
  }
  public func appendingPathComponent(_ component: String) -> URL {
    var text = absoluteString
    var suffix = ""
    if let mark = text.firstIndex(where: { $0 == "?" || $0 == "#" }) {
      suffix = String(text[mark...])
      text = String(text[..<mark])
    }
    if !text.hasSuffix("/") { text += "/" }
    // Foundation percent-encodes what a path cannot hold: "42?role=admin" stays one segment instead of starting a query.
    let segment = component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    return URL(text + segment + suffix)
  }
  public func appendingPathComponent(_ component: String, isDirectory: Bool) -> URL {
    let url = appendingPathComponent(component)
    return isDirectory ? URL(url.absoluteString + "/") : url
  }
  public func deletingLastPathComponent() -> URL {
    var text = absoluteString
    while text.hasSuffix("/") && text.count > 1 { text.removeLast() }
    guard let slash = text.lastIndex(of: "/") else { return self }
    if let range = text.range(of: "://"), slash < range.upperBound { return self }
    return URL(String(text[...slash]))
  }
  public func appendingPathExtension(_ ext: String) -> URL { URL(absoluteString + "." + ext) }
  public func appending(queryItems: [URLQueryItem]) -> URL {
    var text = absoluteString
    var fragment = ""
    if let hash = text.firstIndex(of: "#") { fragment = String(text[hash...]); text = String(text[..<hash]) }
    let encoded = queryItems.map { item in
      item.value.map { _percentEncodeQuery(item.name) + "=" + _percentEncodeQuery($0) } ?? _percentEncodeQuery(item.name)
    }.joined(separator: "&")
    guard !encoded.isEmpty else { return self }
    text += (text.contains("?") ? "&" : "?") + encoded
    return URL(text + fragment)
  }
}

private func _percentEncodeQuery(_ text: String) -> String {
  let hex = Array("0123456789ABCDEF")
  var out = ""
  for byte in text.utf8 {
    let scalar = Character(Unicode.Scalar(byte))
    if scalar.isLetter && byte < 128 || scalar.isNumber && byte < 128 || "-._~".contains(scalar) {
      out.append(scalar)
    } else {
      out.append("%"); out.append(hex[Int(byte >> 4)]); out.append(hex[Int(byte & 15)])
    }
  }
  return out
}

public struct URLComponents: Equatable, Sendable {
  public var scheme: String?
  public var host: String?
  public var port: Int?
  public var path: String = ""
  public var fragment: String?
  public var queryItems: [URLQueryItem]?

  public init() {}
  public init?(url: URL, resolvingAgainstBaseURL: Bool) { self.init(string: url.absoluteString) }
  public init?(string: String) {
    guard let url = URL(string: string) else { return nil }
    scheme = url.scheme
    host = url.host
    port = url.port
    path = url.path
    fragment = url.fragment
    if let query = url.query {
      queryItems = query.split(separator: "&", omittingEmptySubsequences: true).map { pair in
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        return URLQueryItem(name: String(parts[0]), value: parts.count > 1 ? String(parts[1]) : nil)
      }
    }
  }
  public var url: URL? {
    var text = ""
    if let scheme { text += scheme + ":" }
    if let host {
      // A host is one name: a "/", "?", "#", "@" or "\\" in it would move the URL's authority or path, so such a URL
      // is nil rather than a URL to another host.
      guard !host.contains(where: { "/?#@\\".contains($0) || $0.isWhitespace }) else { return nil }
      text += "//" + host
      if let port { text += ":" + String(port) }
      // Foundation's rule: with an authority the path is empty or starts with "/" ("@evil.com" would become userinfo).
      guard path.isEmpty || path.hasPrefix("/") else { return nil }
    } else if path.hasPrefix("//") {
      return nil
    }
    // A "?" or "#" in the path is part of it, not the start of a query or fragment.
    text += path.replacingOccurrences(of: "?", with: "%3F").replacingOccurrences(of: "#", with: "%23")
    if let queryItems, !queryItems.isEmpty { text = URL(text).appending(queryItems: queryItems).absoluteString }
    if let fragment { text += "#" + fragment }
    return URL(string: text)
  }
}

extension TimeZone {
  public init?(abbreviation: String) {
    self.init(identifier: abbreviation)
  }
}

/// `DateFormatter` over the browser's Intl formatting; `dateFormat` is honoured for the ISO shapes servers send.
public final class DateFormatter: @unchecked Sendable {
  public enum Style: Sendable { case none, short, medium, long, full }
  public var dateStyle: Style = .none
  public var timeStyle: Style = .none
  public var dateFormat: String = ""
  public var calendar: Calendar! = .current
  public var timeZone: TimeZone! = .current
  public var locale: Locale! = .current
  public init() {}

  public func date(from string: String) -> Date? {
    _swiftUIWebParseISO8601(string).map { Date(timeIntervalSince1970: $0) }
  }
  public func string(from date: Date) -> String {
    if !dateFormat.isEmpty {
      return _swiftUIWebFormatISO8601(date.timeIntervalSince1970, fractionalSeconds: dateFormat.contains("SSS"))
    }
    var options: [String] = []
    switch dateStyle {
    case .none: break
    case .short: options += ["year=2-digit", "month=numeric", "day=numeric"]
    case .medium: options += ["year=numeric", "month=short", "day=numeric"]
    case .long: options += ["year=numeric", "month=long", "day=numeric"]
    case .full: options += ["weekday=long", "year=numeric", "month=long", "day=numeric"]
    }
    switch timeStyle {
    case .none: break
    case .short: options += ["hour=numeric", "minute=2-digit"]
    case .medium, .long, .full: options += ["hour=numeric", "minute=2-digit", "second=2-digit"]
    }
    return _swiftUIWebFormatDate(date, options: options.joined(separator: ";"), locale: locale?.identifier ?? "")
  }
}

public final class RelativeDateTimeFormatter: @unchecked Sendable {
  public enum UnitsStyle: Sendable { case full, spellOut, short, abbreviated }
  public enum DateTimeStyle: Sendable { case numeric, named }
  public enum Context: Sendable { case unknown, dynamic, standalone, listItem, beginningOfSentence, middleOfSentence }
  public var unitsStyle: UnitsStyle = .full
  public var dateTimeStyle: DateTimeStyle = .numeric
  public var formattingContext: Context = .unknown
  public var locale: Locale! = .current
  public init() {}

  public func localizedString(for date: Date, relativeTo reference: Date) -> String {
    let interval = date.timeIntervalSince(reference)
    // Int64, not Int (32 bits in the browser build, where Int(interval) traps from about 68 years on). Int64(interval)
    // traps for NaN, infinity and magnitudes from 2^63 on; such an interval has no phrase.
    guard interval.isFinite, interval > -0x1p62, interval < 0x1p62 else { return "" }
    let seconds = Int64(interval)
    let magnitude = seconds < 0 ? -seconds : seconds
    let units: [(Int64, String, String)] = [
      (31_536_000, "yr.", "year"), (2_592_000, "mo.", "month"), (604_800, "wk.", "week"),
      (86_400, "day", "day"), (3_600, "hr.", "hour"), (60, "min.", "minute"), (1, "sec.", "second"),
    ]
    let unit = units.first { magnitude >= $0.0 } ?? units[units.count - 1]
    let count = magnitude / unit.0
    let short = unitsStyle == .short || unitsStyle == .abbreviated
    let name = short ? unit.1 : unit.2 + (count == 1 ? "" : "s")
    let phrase = String(count) + " " + name
    return seconds <= 0 ? phrase + " ago" : "in " + phrase
  }
}

extension Date {
  public var timeIntervalSinceNow: TimeInterval { timeIntervalSince1970 - Date().timeIntervalSince1970 }
  public var description: String { _swiftUIWebFormatISO8601(timeIntervalSince1970).replacingOccurrences(of: "Z", with: " +0000").replacingOccurrences(of: "T", with: " ") }
}

extension Duration {
  public struct UnitsFormatStyle: Sendable {
    public enum UnitWidth: Sendable { case narrow, abbreviated, wide }
    public struct Unit: Sendable, Hashable { let name: String; let seconds: Int
      public static let weeks = Unit(name: "w", seconds: 604_800), days = Unit(name: "d", seconds: 86_400)
      public static let hours = Unit(name: "h", seconds: 3_600), minutes = Unit(name: "m", seconds: 60)
      public static let seconds = Unit(name: "s", seconds: 1) }
    let maximumUnitCount: Int?
    public func format(_ duration: Duration) -> String {
      // The seconds as Int64 magnitude: `Int` is 32 bits in the browser build, and negating Int64.min traps.
      var remaining = duration.components.seconds.magnitude
      var parts: [String] = []
      for unit in [Unit.weeks, .days, .hours, .minutes, .seconds] where remaining >= UInt64(unit.seconds) {
        parts.append(String(remaining / UInt64(unit.seconds)) + unit.name)
        remaining %= UInt64(unit.seconds)
        if let maximumUnitCount, parts.count >= maximumUnitCount { break }
      }
      return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }
    public static func units(allowed: Set<Unit>? = nil, width: UnitWidth = .abbreviated, maximumUnitCount: Int? = nil, zeroValueUnitsDisplay: Int = 0) -> UnitsFormatStyle {
      UnitsFormatStyle(maximumUnitCount: maximumUnitCount)
    }
  }
  public func formatted(_ style: UnitsFormatStyle) -> String { style.format(self) }
}

extension Locale {
  /// Foundation's `Locale.LanguageDirection` (`NSLocale.LanguageDirection`), with its raw values.
  public enum LanguageDirection: UInt, Sendable {
    case unknown = 0, leftToRight = 1, rightToLeft = 2, topToBottom = 3, bottomToTop = 4
  }

  public struct LanguageCode: Hashable, Sendable {
    public let identifier: String
    public init(_ identifier: String) { self.identifier = identifier }
    /// The browser does not enumerate ISO codes; the languages Mastodon offers are the common set.
    public static var isoLanguageCodes: [LanguageCode] { languageNames.map { LanguageCode($0.0) } }
  }
  public struct Language: Hashable, Sendable {
    public var languageCode: LanguageCode? { Locale.current.languageCode.map { LanguageCode($0) } }
    public var characterDirection: Locale.LanguageDirection {
      let code = Locale.current.languageCode ?? "en"
      return ["ar", "he", "fa", "ur"].contains(code) ? .rightToLeft : .leftToRight
    }
    public struct Components: Hashable, Sendable {
      public var languageCode: LanguageCode?
      public init(languageCode: Locale.LanguageCode? = nil) { self.languageCode = languageCode }
    }
  }
  public init(languageComponents: Locale.Language.Components) {
    self.init(identifier: languageComponents.languageCode?.identifier ?? "en")
  }
  /// The name of a language in this locale: its own name when the locale is that language, English otherwise.
  public func localizedString(forLanguageCode code: String) -> String? {
    guard let entry = Locale.languageNames.first(where: { $0.0 == code }) else { return nil }
    return identifier == code ? entry.2 : entry.1
  }
  fileprivate static let languageNames: [(String, String, String)] = [
    ("en", "English", "English"), ("pt", "Portuguese", "Português"), ("es", "Spanish", "Español"),
    ("fr", "French", "Français"), ("de", "German", "Deutsch"), ("it", "Italian", "Italiano"),
    ("ja", "Japanese", "日本語"), ("ko", "Korean", "한국어"), ("zh", "Chinese", "中文"),
    ("ru", "Russian", "Русский"), ("nl", "Dutch", "Nederlands"), ("sv", "Swedish", "Svenska"),
    ("pl", "Polish", "Polski"), ("tr", "Turkish", "Türkçe"), ("ar", "Arabic", "العربية"),
    ("uk", "Ukrainian", "Українська"),
  ]
}


/// The components of an absolute or relative URL string as the browser's fetch parser (WHATWG URL) reads them. Kept
/// outside the guard above so the parser builds, and is tested, on every host; the Embedded `URL` accessors read it.
struct _EmbeddedURLParts: Equatable {
  var scheme: String?
  var host: String?
  var port: Int?
  var path: String

  /// Returns nil when the string is an absolute URL whose authority WHATWG rejects (empty or forbidden host, unclosed
  /// IPv6 bracket, port that is not 0...65535). A relative string parses with no scheme, host or port.
  static func parse(_ string: String) -> _EmbeddedURLParts? {
    // WHATWG drops tab and newline bytes everywhere, and leading and trailing C0 controls and spaces.
    var text: [UInt8] = []
    for byte in string.utf8 where byte != 0x09 && byte != 0x0A && byte != 0x0D { text.append(byte) }
    var first = 0
    var last = text.count
    while first < last && text[first] <= 0x20 { first += 1 }
    while last > first && text[last - 1] <= 0x20 { last -= 1 }
    let bytes = Array(text[first..<last])

    // A scheme is an ASCII letter, then letters, digits, '+', '-' or '.', then ':'. It is case-insensitive.
    var index = 0
    var scheme: String? = nil
    if let head = bytes.first, isASCIILetter(head) {
      var end = 0
      while end < bytes.count && (isASCIILetter(bytes[end]) || isASCIIDigit(bytes[end]) || bytes[end] == 0x2B || bytes[end] == 0x2D || bytes[end] == 0x2E) {
        end += 1
      }
      if end < bytes.count && bytes[end] == 0x3A {
        scheme = String(decoding: lowercasedASCII(bytes[0..<end]), as: UTF8.self)
        index = end + 1
      }
    }
    // A relative string with no scheme is parsed as if against a special base, so '\' counts as '/' there too.
    let special = scheme.map { ["ftp", "file", "http", "https", "ws", "wss"].contains($0) } ?? true

    // Where the authority begins. Special schemes skip every slash ("http:///h/" has host h); "file" and a scheme-less
    // string need exactly two; other schemes need "//" to have one at all.
    var authorityStart: Int? = nil
    let doubleSlash = bytes.count >= index + 2 && isSlash(bytes[index], special) && isSlash(bytes[index + 1], special)
    if scheme == nil || scheme == "file" {
      if doubleSlash { authorityStart = index + 2 }
    } else if special {
      var cursor = index
      while cursor < bytes.count && isSlash(bytes[cursor], true) { cursor += 1 }
      authorityStart = cursor
    } else if doubleSlash {
      authorityStart = index + 2
    }

    // The authority runs to the first '/', '?' or '#', and to '\' for special schemes.
    var authority: ArraySlice<UInt8> = []
    var pathFrom = 0
    if let start = authorityStart {
      var end = start
      while end < bytes.count && !isAuthorityEnd(bytes[end], special) { end += 1 }
      authority = bytes[start..<end]
      pathFrom = end
    }

    // The path runs to the first '?' or '#'. Without an authority it is the whole string (as before this parser).
    var pathEnd = pathFrom
    while pathEnd < bytes.count && bytes[pathEnd] != 0x3F && bytes[pathEnd] != 0x23 { pathEnd += 1 }
    var pathBytes = Array(bytes[pathFrom..<pathEnd])
    if authorityStart != nil {
      if special { for i in pathBytes.indices where pathBytes[i] == 0x5C { pathBytes[i] = 0x2F } }
    } else {
      pathBytes = Array(bytes[0..<pathEnd])
    }

    // Userinfo ends at the last '@'. The host ends at the first ':' (or at the closing ']' of an IPv6 literal).
    var hostPort = authority
    if let at = authority.lastIndex(of: 0x40) { hostPort = authority[(at + 1)...] }
    var host: [UInt8] = []
    var portDigits: ArraySlice<UInt8>? = nil
    var isLiteral = false
    if hostPort.first == 0x5B {
      guard let close = hostPort.firstIndex(of: 0x5D) else { return nil }
      host = Array(hostPort[hostPort.startIndex...close])
      let inner = host.dropFirst().dropLast()
      guard !inner.isEmpty, inner.allSatisfy({ isHexDigit($0) || $0 == 0x3A || $0 == 0x2E }) else { return nil }
      let rest = hostPort[(close + 1)...]
      guard rest.isEmpty || rest.first == 0x3A else { return nil }
      if !rest.isEmpty { portDigits = rest.dropFirst() }
      isLiteral = true
    } else if let colon = hostPort.firstIndex(of: 0x3A) {
      host = Array(hostPort[hostPort.startIndex..<colon])
      portDigits = hostPort[(colon + 1)...]
    } else {
      host = Array(hostPort)
    }

    var port: Int? = nil
    if let digits = portDigits, !digits.isEmpty {
      var value = 0
      for byte in digits {
        guard isASCIIDigit(byte) else { return nil }
        value = value * 10 + Int(byte - 0x30)
        guard value <= 65_535 else { return nil }
      }
      port = value
    }

    var hostOut: String? = nil
    if host.isEmpty {
      // A special scheme needs a host (file excepted); a non-special scheme may have none; neither may carry a port.
      guard scheme == "file" || (scheme != nil && !special) || authorityStart == nil else { return nil }
      if let digits = portDigits, !digits.isEmpty { return nil }
    } else {
      if !isLiteral {
        // Percent-decoding and IDNA are not done here, so a '%' or a forbidden code point means the host is not one
        // this parser can name.
        for byte in host where byte <= 0x20 || byte == 0x7F || [0x23, 0x2F, 0x3A, 0x3C, 0x3E, 0x3F, 0x40, 0x5B, 0x5C, 0x5D, 0x5E, 0x7C, 0x25].contains(byte) {
          return nil
        }
      }
      if special {
        host = lowercasedASCII(host)
      }
      hostOut = String(decoding: host, as: UTF8.self)
    }

    return _EmbeddedURLParts(
      scheme: scheme,
      host: hostOut,
      port: port,
      path: String(decoding: pathBytes, as: UTF8.self)
    )
  }

  private static func isSlash(_ byte: UInt8, _ special: Bool) -> Bool {
    byte == 0x2F || (special && byte == 0x5C)
  }
  private static func isAuthorityEnd(_ byte: UInt8, _ special: Bool) -> Bool {
    byte == 0x2F || byte == 0x3F || byte == 0x23 || (special && byte == 0x5C)
  }
  private static func isASCIILetter(_ byte: UInt8) -> Bool {
    (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
  }
  private static func isASCIIDigit(_ byte: UInt8) -> Bool {
    byte >= 0x30 && byte <= 0x39
  }
  private static func isHexDigit(_ byte: UInt8) -> Bool {
    isASCIIDigit(byte) || (byte >= 0x41 && byte <= 0x46) || (byte >= 0x61 && byte <= 0x66)
  }
  private static func lowercasedASCII<Bytes: Sequence>(_ bytes: Bytes) -> [UInt8] where Bytes.Element == UInt8 {
    bytes.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
  }
}
