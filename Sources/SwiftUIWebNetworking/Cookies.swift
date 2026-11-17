// Foundation's `HTTPCookie` and `HTTPCookieStorage`, on every host.
//
// In the browser the jar is the page's: a read returns the document's non-HttpOnly cookies, a write assigns `document.cookie`
// where the browser allows it. HttpOnly cookies are managed by the browser and are invisible here; they are never
// written from script. Requests do not consult this storage: the browser attaches cookies itself, according to the
// request's credentials mode (see `URLSessionConfiguration.credentialsPolicy`).

@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebLocking

/// Foundation's `HTTPCookiePropertyKey`, with Foundation's raw values. Only the keys a browser cookie can carry are
/// spelled here; Foundation has no `httpOnly` constant either (the key is `"HttpOnly"`).
public struct HTTPCookiePropertyKey: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }

  public static let name = HTTPCookiePropertyKey("Name")
  public static let value = HTTPCookiePropertyKey("Value")
  public static let domain = HTTPCookiePropertyKey("Domain")
  public static let path = HTTPCookiePropertyKey("Path")
  public static let secure = HTTPCookiePropertyKey("Secure")
  public static let version = HTTPCookiePropertyKey("Version")
  public static let expires = HTTPCookiePropertyKey("Expires")
}

/// A cookie as the browser reports it to script. Immutable; create one with `init?(properties:)`.
public final class HTTPCookie: @unchecked Sendable {
  /// Apple's `HTTPCookie.AcceptPolicy`: which cookies a storage keeps.
  public enum AcceptPolicy: UInt, Sendable, Hashable {
    case always = 0
    case never = 1
    case onlyFromMainDocumentDomain = 2
  }

  public let name: String
  public let value: String
  public let domain: String
  public let path: String
  public let expiresDate: Date?
  public let isSecure: Bool
  public let isHTTPOnly: Bool
  public let version: Int

  /// `true` when the cookie has no expiry date and lasts for the browsing session.
  public var isSessionOnly: Bool { expiresDate == nil }

  /// Apple's `init?(properties:)`. Requires a name, a value, a domain (possibly empty: a host-only cookie for the
  /// page that writes it) and a path, each a `String`. `secure` and `httpOnly` read `Bool` or `"TRUE"`/`"1"`;
  /// `version` reads `Int` or a numeric string; `expires` reads a `Date`. Unreadable values are ignored.
  public init?(properties: [HTTPCookiePropertyKey: Any]) {
    guard let name = properties[.name] as? String, let value = properties[.value] as? String,
          let domain = properties[.domain] as? String, let path = properties[.path] as? String else { return nil }
    guard _cookieIsValidName(name), _cookieIsValidValue(value), path.hasPrefix("/"),
          _cookieIsValidPath(path), _cookieIsValidDomain(domain) else { return nil }
    self.name = name
    self.value = value
    self.domain = domain
    self.path = path
    self.expiresDate = properties[.expires] as? Date
    self.isSecure = _cookieFlag(properties[.secure])
    self.isHTTPOnly = _cookieFlag(properties[HTTPCookiePropertyKey("HttpOnly")])
    if let version = properties[.version] as? Int {
      self.version = version
    } else {
      self.version = Int(properties[.version] as? String ?? "") ?? 0
    }
  }

  /// A cookie read from `document.cookie`: the page's host, the default path and no attributes script cannot see.
  package init(scriptVisibleName name: String, value: String, domain: String) {
    self.name = name
    self.value = value
    self.domain = domain
    self.path = "/"
    self.expiresDate = nil
    self.isSecure = false
    self.isHTTPOnly = false
    self.version = 0
  }

  package init(name: String, value: String, domain: String, path: String, expiresDate: Date?, isSecure: Bool, isHTTPOnly: Bool) {
    self.name = name
    self.value = value
    self.domain = domain
    self.path = path
    self.expiresDate = expiresDate
    self.isSecure = isSecure
    self.isHTTPOnly = isHTTPOnly
    self.version = 0
  }
}

/// The browser's cookie jar as a Foundation-shaped storage. `shared` is the only storage a browser has.
public final class HTTPCookieStorage: @unchecked Sendable {
  public static let shared = HTTPCookieStorage()

  private let policy = _CookiePolicyBox()

  package init() {}

  /// Apple's `cookieAcceptPolicy`. `.never` keeps `setCookie` from writing; the browser decides everything else.
  public var cookieAcceptPolicy: HTTPCookie.AcceptPolicy {
    get { policy.value }
    set { policy.value = newValue }
  }

  /// The cookies script can see on the current page, or `nil` when there are none or the host has no document.
  public var cookies: [HTTPCookie]? {
    let visible = CookieJarRuntime.visibleCookies()
    return visible.isEmpty ? nil : visible
  }

  /// The visible cookies that a request to `url` would carry: the domain and path match and a secure cookie needs an
  /// `https` URL.
  public func cookies(for url: URL) -> [HTTPCookie]? {
    let target = _cookieURLParts(url)
    let matches = CookieJarRuntime.visibleCookies().filter { cookie in
      guard _cookieDomain(target.host, matches: cookie.domain) else { return false }
      guard target.path.hasPrefix(cookie.path) else { return false }
      return _cookieSchemeAllows(cookieIsSecure: cookie.isSecure, pageIsSecure: target.isSecure)
    }
    return matches.isEmpty ? nil : matches
  }

  /// Writes `cookie` into the page's cookie jar, as script would. HttpOnly cookies cannot be written from script and
  /// are dropped; so are cookies the browser would refuse (an invalid name or value, or a `Secure` cookie on plain HTTP).
  public func setCookie(_ cookie: HTTPCookie) {
    guard cookieAcceptPolicy != .never, !cookie.isHTTPOnly, let line = _cookieSetLine(cookie) else { return }
    _ = CookieJarRuntime.write(line)
  }

  /// Apple's `setCookies(_:for:mainDocumentURL:)`. The URL does not change where the browser stores a cookie: the
  /// page's own jar takes it.
  public func setCookies(_ cookies: [HTTPCookie], for URL: URL?, mainDocumentURL: URL?) {
    for cookie in cookies { setCookie(cookie) }
  }

  /// Expires `cookie` in the page's jar.
  public func deleteCookie(_ cookie: HTTPCookie) {
    let expired = HTTPCookie(name: cookie.name, value: "", domain: cookie.domain, path: cookie.path,
                             expiresDate: Date(timeIntervalSince1970: 0), isSecure: cookie.isSecure, isHTTPOnly: false)
    guard let line = _cookieSetLine(expired) else { return }
    _ = CookieJarRuntime.write(line)
  }
}

/// Non-generic holder for the policy: the browser storage is shared, so reads and writes take this lock.
private final class _CookiePolicyBox: @unchecked Sendable {
  private var stored = HTTPCookie.AcceptPolicy.onlyFromMainDocumentDomain
  private let lock = _RuntimeLock()
  var value: HTTPCookie.AcceptPolicy {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}

/// Host hooks for the browser cookie jar. `SwiftUIWebBrowser` installs them with `BrowserCookieJar`; without a host
/// the jar is empty and writes are dropped, as in a worker that has no document.
package enum CookieJarRuntime {
  package typealias Reader = @Sendable () -> (cookieString: String, host: String, isSecurePage: Bool)?
  package typealias Writer = @Sendable (String) -> Bool

  private final class Hooks: @unchecked Sendable {
    var read: Reader?
    var write: Writer?
    let lock = _RuntimeLock()
  }
  private static let hooks = Hooks()

  package static func install(read: Reader?, write: Writer?) {
    hooks.lock.withLock {
      hooks.read = read
      hooks.write = write
    }
  }

  fileprivate static func visibleCookies() -> [HTTPCookie] {
    let read = hooks.lock.withLock { hooks.read }
    guard let snapshot = read?() else { return [] }
    var cookies: [HTTPCookie] = []
    for part in snapshot.cookieString.split(separator: ";") {
      let pair = part.drop(while: { $0 == " " })
      guard !pair.isEmpty else { continue }
      if let equals = pair.firstIndex(of: "=") {
        let name = String(pair[pair.startIndex..<equals])
        let value = String(pair[pair.index(after: equals)...])
        cookies.append(HTTPCookie(scriptVisibleName: name, value: value, domain: snapshot.host))
      } else {
        // A nameless cookie is a value with an empty name, as browsers report it.
        cookies.append(HTTPCookie(scriptVisibleName: "", value: String(pair), domain: snapshot.host))
      }
    }
    return cookies
  }

  fileprivate static func write(_ line: String) -> Bool {
    let write = hooks.lock.withLock { hooks.write }
    return write?(line) ?? false
  }

  private final class Observers: @unchecked Sendable {
    var handlers: [UInt64: @MainActor () -> Void] = .init()
    var nextID: UInt64 = 0
    let lock = _RuntimeLock()
  }
  private static let observers = Observers()

  /// Runs `handler` on the main actor at each change of the page's cookies. The returned closure stops it.
  package static func observe(_ handler: @escaping @MainActor () -> Void) -> @Sendable () -> Void {
    let id = observers.lock.withLock { () -> UInt64 in
      observers.nextID += 1
      observers.handlers[observers.nextID] = handler
      return observers.nextID
    }
    return { observers.lock.withLock { observers.handlers[id] = nil } }
  }

  /// The worker's cookie mirror now holds the page's new cookies: every observer runs once, before the next publication.
  @MainActor package static func notifyChanged() {
    let active = observers.lock.withLock { Array(observers.handlers.values) }
    for handler in active { handler() }
  }
}

extension HTTPCookieStorage {
  /// Calls `handler` on the main actor at each change of the page's cookies (in any tab, or from a server response),
  /// once the worker's copy holds the new jar. Apple reports the same through `NSHTTPCookieManagerCookiesChangedNotification`.
  /// The returned closure stops the observation.
  @_spi(Browser) @discardableResult
  public func observeChanges(_ handler: @escaping @MainActor () -> Void) -> @Sendable () -> Void {
    CookieJarRuntime.observe(handler)
  }
}

// MARK: - Helpers

private func _cookieFlag(_ value: Any?) -> Bool {
  if let flag = value as? Bool { return flag }
  guard let text = value as? String else { return false }
  return text == "TRUE" || text == "true" || text == "1" || text == "YES"
}

/// Names and values cannot carry the separators a `Set-Cookie` line uses, nor control characters.
private func _cookieIsValidName(_ name: String) -> Bool {
  !name.isEmpty && name.utf8.allSatisfy { $0 > 0x20 && $0 < 0x7F && $0 != 0x3B && $0 != 0x3D && $0 != 0x2C }
}

private func _cookieIsValidValue(_ value: String) -> Bool {
  value.utf8.allSatisfy { $0 >= 0x20 && $0 < 0x7F && $0 != 0x3B && $0 != 0x2C }
}

/// A `Path` attribute value: printable ASCII without the attribute separator `;` and without spaces. Non-ASCII bytes
/// pass through unchanged, since they are not structure in the attribute line.
private func _cookieIsValidPath(_ path: String) -> Bool {
  path.utf8.allSatisfy { ($0 >= 0x21 && $0 < 0x7F && $0 != 0x3B) || $0 >= 0x80 }
}

/// A `Domain` attribute value: empty (a host-only cookie), or a host of letters, digits, `-` and `.` with an optional
/// leading dot and no empty labels. Every other byte could start a new attribute or change the host.
private func _cookieIsValidDomain(_ domain: String) -> Bool {
  if domain.isEmpty { return true }
  var bytes = Array(domain.utf8)
  if bytes.first == 0x2E { bytes.removeFirst() }
  guard let last = bytes.last, last != 0x2E else { return false }
  var previous: UInt8 = 0x2E
  for byte in bytes {
    let isLetterOrDigit = (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    guard isLetterOrDigit || byte == 0x2D || byte == 0x2E else { return false }
    if byte == 0x2E && previous == 0x2E { return false }
    previous = byte
  }
  return true
}

/// The attribute line for `document.cookie`, or `nil` when the cookie cannot be written.
private func _cookieSetLine(_ cookie: HTTPCookie) -> String? {
  guard _cookieIsValidName(cookie.name), _cookieIsValidValue(cookie.value) else { return nil }
  let path = cookie.path.isEmpty ? "/" : cookie.path
  guard _cookieIsValidPath(path), _cookieIsValidDomain(cookie.domain) else { return nil }
  var line = "\(cookie.name)=\(cookie.value); Path=\(path)"
  if !cookie.domain.isEmpty { line += "; Domain=\(cookie.domain)" }
  if let expires = cookie.expiresDate { line += "; Expires=\(_cookieHTTPDate(expires))" }
  if cookie.isSecure { line += "; Secure" }
  return line
}

/// The scheme, host and path of an absolute URL. Embedded's `URL` keeps only the string, so this parses it.
/// A secure cookie is sent only to an https page; any other cookie is sent over either scheme.
func _cookieSchemeAllows(cookieIsSecure: Bool, pageIsSecure: Bool) -> Bool {
  if !cookieIsSecure { return true }
  return pageIsSecure
}

private func _cookieURLParts(_ url: URL) -> (host: String, path: String, isSecure: Bool) {
  let text = url.absoluteString
  // Embedded's String has no `range(of:)`; the authority starts after the first "//" that follows the scheme colon.
  guard let colon = text.firstIndex(of: ":") else { return ("", "/", false) }
  // The scheme is case-insensitive (RFC 3986), so HTTPS:// is secure too.
  let scheme = text[text.startIndex..<colon].lowercased()
  let isSecure = scheme == "https"
  // For http and https a browser reads a backslash as a slash, so it also ends the authority and separates the path.
  let isWeb = isSecure || scheme == "http"
  let afterColon = text.index(after: colon)
  guard text[afterColon...].hasPrefix("//") else { return ("", "/", false) }
  let rest = text[text.index(afterColon, offsetBy: 2)...]
  let authorityEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" || (isWeb && $0 == "\\") }) ?? rest.endIndex
  var host = String(rest[rest.startIndex..<authorityEnd])
  if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
  if let colon = host.lastIndex(of: ":") { host = String(host[host.startIndex..<colon]) }
  var path = "/"
  if authorityEnd < rest.endIndex, rest[authorityEnd] == "/" || (isWeb && rest[authorityEnd] == "\\") {
    let tail = rest[authorityEnd...].prefix(while: { $0 != "?" && $0 != "#" })
    path = String(tail.map { isWeb && $0 == "\\" ? "/" : $0 })
  }
  return (host.lowercased(), path, isSecure)
}

/// RFC 6265 domain matching: the host is the cookie's domain or a subdomain of it.
private func _cookieDomain(_ host: String, matches domain: String) -> Bool {
  var expected = domain.lowercased()
  // A domain cookie (a leading dot) reaches the domain's subdomains too. A host-only cookie, which is what script
  // sees for the page's own cookies, reaches its host only.
  if expected.hasPrefix(".") {
    expected.removeFirst()
    guard !expected.isEmpty else { return false }
    return host == expected || host.hasSuffix("." + expected)
  }
  return !expected.isEmpty && host == expected
}

/// `Sun, 06 Nov 1994 08:49:37 GMT`, the cookie date format.
private func _cookieHTTPDate(_ date: Date) -> String {
  // Seconds in Int64: Int is 32 bits in the browser build, and an expiry after 2038 is past 2^31. Days and the seconds of
  // the day fit an Int.
  let seconds = Int64(max(-62_135_596_800, min(253_402_300_799, date.timeIntervalSince1970.rounded(.down))))
  var days = Int(seconds / 86_400)
  var remainder = Int(seconds % 86_400)
  if remainder < 0 { remainder += 86_400; days -= 1 }
  let weekdays = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"]
  let weekday = weekdays[((days % 7) + 7) % 7]
  // Civil date from a day count since 1970-01-01 (Howard Hinnant's algorithm).
  let z = days + 719_468
  let era = (z >= 0 ? z : z - 146_096) / 146_097
  let dayOfEra = z - era * 146_097
  let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
  let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
  let monthIndex = (5 * dayOfYear + 2) / 153
  let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
  let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
  let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
  let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
  let clock = "\(pad(remainder / 3600)):\(pad(remainder % 3600 / 60)):\(pad(remainder % 60))"
  return "\(weekday), \(pad(day)) \(months[month - 1]) \(year) \(clock) GMT"
}
