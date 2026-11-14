@_spi(Renderer) import SwiftUIWebLocking
import SwiftUIWebBrowserIO

/// Why the item store could not be read or written.
public enum WebSecurityError: Error, Equatable, Sendable {
  /// The browser offers no IndexedDB or no Web Crypto: an insecure context (plain HTTP other than
  /// localhost), storage disabled by policy, or a browser without these APIs. Retrying will not help;
  /// the `SecItem…` calls answer `errSecNotAvailable`.
  case unavailable(String)
  /// The store failed this time (a blocked or full database, a cancelled request); a later attempt
  /// may succeed.
  case storage(String)
}

/// Where `WebSecurity` keeps its encrypted items. The browser default is `WebCryptoSecretStore`
/// (Web Crypto + IndexedDB); tests and hosts without a browser install `InMemorySecretStore`.
/// Class-bound, because Embedded Swift only has existentials of class-bound protocols.
/// A store only ever sees item ids and the records `WebSecurity` serializes; encryption, and the
/// key, belong to the store's implementation.
public protocol WebSecretStore: AnyObject, Sendable {
  func loadAll() async throws(WebSecurityError) -> [(id: String, value: [UInt8])]
  func save(_ value: [UInt8], id: String) async throws(WebSecurityError)
  func remove(id: String) async throws(WebSecurityError)
  func removeAll() async throws(WebSecurityError)
}

/// The browser store: each record AES-GCM encrypted under a non-extractable Web Crypto key, in
/// IndexedDB. Needs a secure context (HTTPS or localhost). See `WebSecurity` for what this protects
/// against and what it does not.
public final class WebCryptoSecretStore: WebSecretStore {
  private let store: BrowserSecureStore

  public init(name: String = "keychain") { store = BrowserSecureStore(name: name) }

  public func loadAll() async throws(WebSecurityError) -> [(id: String, value: [UInt8])] {
    do { return try await store.loadAll() } catch { throw Self.translate(error) }
  }
  public func save(_ value: [UInt8], id: String) async throws(WebSecurityError) {
    do { try await store.save(value, id: id) } catch { throw Self.translate(error) }
  }
  public func remove(id: String) async throws(WebSecurityError) {
    do { try await store.remove(id: id) } catch { throw Self.translate(error) }
  }
  public func removeAll() async throws(WebSecurityError) {
    do { try await store.removeAll() } catch { throw Self.translate(error) }
  }

  /// The browser host reports a missing IndexedDB or Web Crypto as code -7.
  private static func translate(_ error: BrowserIOError) -> WebSecurityError {
    error.code == -7 ? .unavailable(error.message) : .storage(error.message)
  }
}

/// Items kept in process memory only: nothing survives the page. For tests and previews; `failure`
/// makes every operation fail, to exercise an unavailable or failing store.
public final class InMemorySecretStore: WebSecretStore {
  private let items = _Locked<[String: [UInt8]]>([:])
  private let failure = _Locked<WebSecurityError?>(nil)

  public init(_ items: [String: [UInt8]] = [:], failure: WebSecurityError? = nil) {
    self.items.withLock { $0 = items }
    self.failure.withLock { $0 = failure }
  }

  public var snapshot: [String: [UInt8]] { items.withLock { $0 } }
  public func fail(with error: WebSecurityError?) { failure.withLock { $0 = error } }

  public func loadAll() async throws(WebSecurityError) -> [(id: String, value: [UInt8])] {
    try check()
    return items.withLock { items in items.keys.sorted().map { (id: $0, value: items[$0] ?? []) } }
  }
  public func save(_ value: [UInt8], id: String) async throws(WebSecurityError) { try check(); items.withLock { $0[id] = value } }
  public func remove(id: String) async throws(WebSecurityError) { try check(); items.withLock { $0[id] = nil } }
  public func removeAll() async throws(WebSecurityError) { try check(); items.withLock { $0.removeAll() } }

  private func check() throws(WebSecurityError) {
    if let error = failure.withLock({ $0 }) { throw error }
  }
}
