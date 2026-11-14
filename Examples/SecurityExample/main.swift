import SwiftUIWeb
import SwiftUIWebBrowser
@_spi(Browser) import SwiftUIWebNetworking
import SwiftUIWebSecurity

/// The keychain in a real browser: the first load stores a secret with `SecItemAdd`, a reload finds
/// it again with `SecItemCopyMatching`, and "Forget" deletes it. The bytes at rest are AES-GCM
/// ciphertext in IndexedDB; Tools/test-security-browser.mjs checks all three.
@main
struct SecurityExample: BrowserApp {
  var body: some Scene {
    WindowGroup { KeychainDemo() }
  }
}

private struct KeychainDemo: View {
  @State private var status = "Unlocking…"
  @State private var forgetRequest = 0
  @State private var cookies = "Cookies: none"

  var body: some View {
    VStack {
      Text("Web keychain")
      Text(status).accessibilityIdentifier("keychain-status")
      Text(cookies).accessibilityIdentifier("cookie-status")
      Button("Forget") { forgetRequest += 1 }
    }
    .padding()
    .task { await load() }
    .task { cookies = KeychainDemo.exerciseCookies() }
    .task {
      // Another tab, or a response handled on the main thread, changes the jar: show what the page sees now.
      HTTPCookieStorage.shared.observeChanges { cookies = KeychainDemo.cookieStatus() }
    }
    .task(id: forgetRequest) {
      guard forgetRequest > 0 else { return }
      let deleted = SecItemDelete(KeychainDemo.query)
      await WebSecurity.synchronize()
      status = deleted == errSecSuccess ? "Forgotten" : "Delete failed: \(deleted)"
    }
  }

  private static let query: CFDictionary = [
    kSecClass: kSecClassGenericPassword, kSecAttrService: "swiftuiweb.example", kSecAttrAccount: "demo",
  ]

  /// The page's cookie jar through SwiftUIWebNetworking's stand-in: a script-visible cookie is written and read back.
  /// The HttpOnly cookie is refused by the jar (script cannot write it), so it never appears here.
  private static func exerciseCookies() -> String {
    let storage = HTTPCookieStorage.shared
    if let visible = HTTPCookie(properties: [.name: "swui_pref", .value: "compact", .domain: "", .path: "/"]) {
      storage.setCookie(visible)
    }
    if let hidden = HTTPCookie(properties: [.name: "swui_session", .value: "hidden", .domain: "", .path: "/", HTTPCookiePropertyKey("HttpOnly"): true]) {
      storage.setCookie(hidden)
    }
    return cookieStatus()
  }

  /// What `HTTPCookieStorage.shared` reports for the page right now, sorted by name: the jar's order is unspecified
  /// (WebKit can list a cookie written in another tab first).
  private static func cookieStatus() -> String {
    let names = (HTTPCookieStorage.shared.cookies ?? []).map { "\($0.name)=\($0.value)" }.sorted()
    return "Cookies: " + (names.isEmpty ? "none" : names.joined(separator: "; "))
  }

  private func load() async {
    do { try await WebSecurity.unlock() } catch {
      switch error {
      case .unavailable:
        // Every call now answers errSecNotAvailable; show that it does.
        status = "Not available: \(SecItemCopyMatching(KeychainDemo.query, nil))"
      case .storage:
        status = "Locked: storage failed"
      }
      return
    }
    var query = KeychainDemo.query
    query[kSecReturnData] = kCFBooleanTrue!
    var item: CFTypeRef?
    let found = SecItemCopyMatching(query as CFDictionary, &item)
    if found == errSecSuccess, let bytes = item?.data {
      status = "Found: " + String(decoding: bytes, as: UTF8.self)
      return
    }
    var attributes = KeychainDemo.query
    attributes[kSecValueData] = .bytes("s3cret-from-swift".utf8)
    let added = SecItemAdd(attributes as CFDictionary, nil)
    await WebSecurity.synchronize()
    status = added == errSecSuccess ? "Added" : "Add failed: \(added)"
  }
}
