@_spi(Renderer) import SwiftUIWebLocking

/// The browser backend of the Security.framework-shaped API in this module. It uses the strongest
/// mechanism a page has, which is not the Keychain's; Documentation/Security/WEB_SECURITY.md
/// compares the two in full.
///
/// **What it does.** Each item, attributes included, is AES-GCM 256 encrypted with a fresh 96-bit
/// IV under one Web Crypto key per store. The key is created with `extractable: false` and the
/// usages `encrypt` and `decrypt` only, and is kept as a `CryptoKey` in the origin's IndexedDB next
/// to the ciphertext. The item id is authenticated data, so a ciphertext moved onto another item does
/// not decrypt. The key's bytes never reach JavaScript, Swift or the WASM; only plaintext the app
/// itself stores or reads crosses into Swift.
///
/// **What that protects against.** Reading the key out through any web API (`exportKey` refuses);
/// finding item values or attributes by looking at storage (dev tools, a storage dump of the
/// database); another origin's code, which cannot open this origin's IndexedDB.
///
/// **What it does not protect against.** Code running in this origin: a cross-site scripting bug, a
/// compromised dependency, an extension with access to the page. Such code can open the same
/// IndexedDB, get the same `CryptoKey` and call `crypto.subtle.decrypt` with it, exactly as this
/// module does; non-extractable stops it from taking the key away, not from using it while it runs.
/// Nor against someone with the browser profile on disk: the key is stored in that profile, protected
/// by the operating system's user account, not by a device secret. There is no device-lock state,
/// biometric gate or per-app access control: `kSecAttrAccessible` values are stored but not enforced.
/// The defense that matters most is keeping foreign code out of the origin (a strict
/// Content-Security-Policy, few third-party scripts).
///
/// **Lifetime.** Items persist across reloads, tabs and browser restarts in the same profile, until
/// the user or the browser clears the site's data: private windows discard them when closed, storage
/// pressure can evict them, and some browsers delete script-written storage of sites not visited for
/// a while. Treat them as a cache of secrets the app can obtain again, never as the only copy. Each
/// tab reads the store when it unlocks; a change made in another tab appears after the next unlock.
///
/// **Sign-in sessions are not items.** The server sets an `HttpOnly`, `Secure`, `SameSite` cookie
/// and the browser sends it; no code in the page, this WASM included, can read, store or receive it.
/// `kSecClassInternetPassword` returns `errSecUnimplemented`; `WebSecurity.Session` reports whether
/// the session is active. Preferences belong in `UserDefaults` (`localStorage`) and tab state in
/// `@SceneStorage` (`sessionStorage`), never secrets.
public enum WebSecurity {
  private static let installed = _Locked(_SecKeychain(store: WebCryptoSecretStore()))

  static var keychain: _SecKeychain { installed.withLock { $0 } }

  /// Replaces the item store, for tests, previews or a host without IndexedDB. The new store is
  /// locked until `unlock()` loads it.
  public static func install(store: any WebSecretStore) {
    installed.withLock { $0 = _SecKeychain(store: store) }
  }

  /// Decrypts the stored items into memory so the `SecItem…` calls can answer. Call it once at
  /// launch (for example in the root view's `.task`); later calls return at once. Throws
  /// `.unavailable` without IndexedDB or Web Crypto (Web Crypto needs HTTPS or localhost), after which
  /// the calls answer `errSecNotAvailable`; `.storage` for a failure a later call may not repeat.
  public static func unlock() async throws(WebSecurityError) { try await keychain.unlock() }

  /// Drops the decrypted items from memory once pending writes finish, for example at sign-out;
  /// the calls answer `errSecInteractionNotAllowed` until the next `unlock()`. After it returns the
  /// store stays locked even if an earlier `unlock()` was still loading: that unlock returns
  /// without unlocking, so check `isUnlocked` when a lock may have overtaken it.
  public static func lock() async { await keychain.lock() }

  public static var isUnlocked: Bool { keychain.isUnlocked }

  /// Waits until every change made so far is encrypted and written.
  public static func synchronize() async { await keychain.synchronize() }

  /// The last error writing an item; the in-memory item is unaffected, but it may not survive a
  /// reload.
  public static var lastPersistenceError: WebSecurityError? { keychain.lastPersistenceError }
}
