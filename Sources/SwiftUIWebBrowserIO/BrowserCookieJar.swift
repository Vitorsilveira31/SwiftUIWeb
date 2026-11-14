/// The browser's own cookie jar as script sees it (`document.cookie`). Foundation's `HTTPCookieStorage` on Embedded is
/// built on this. Reads never include HttpOnly cookies, and a script cannot write them, so the browser keeps those
/// to itself; that is the one part of the jar SwiftUIWeb cannot see or change.
public struct BrowserCookieJar: Sendable {
  /// What a read of the jar returned: the `name=value; ...` string, the page host and whether the page is secure.
  public struct Snapshot: Sendable, Equatable {
    public let cookieString: String
    public let host: String
    public let isSecurePage: Bool
  }

  public init() {}

  /// The document's cookies. Throws code -7 when the host has no document (a worker, for example).
  public func snapshot() throws(BrowserIOError) -> Snapshot {
    var command = IOWriter()
    command.u32(0)
    command.text("")
    var input = try IORuntime.sync(_BrowserIOProtocol.cookies, command)
    let cookieString = input.text()
    let host = input.text()
    let secure = input.u32() != 0
    if let error = input.finish() { throw error }
    return Snapshot(cookieString: cookieString, host: host, isSecurePage: secure)
  }

  /// Assigns one `Set-Cookie`-style string to `document.cookie`, the way a script does. The browser applies its own
  /// rules (domain, path, Secure on plain HTTP, SameSite) and drops what it refuses without an error.
  public func write(_ setCookie: String) throws(BrowserIOError) {
    var command = IOWriter()
    command.u32(1)
    command.text(setCookie)
    var result = try IORuntime.sync(_BrowserIOProtocol.cookies, command)
    if let error = result.finish() { throw error }
  }
}
