import Testing
@testable import SwiftUIWebSecurity

/// What the item store does around the calls: a browser without IndexedDB or Web Crypto, a store that
/// fails once, locking, a write that does not persist, and two tabs on the same store.
extension GlobalKeychainSuites {
@Suite(.serialized)
struct WebSecurityLifecycleTests {
  private let item: CFDictionary = [kSecClass: kSecClassGenericPassword, kSecAttrService: "studio", kSecAttrAccount: "ana"]

  private func adding(_ value: [UInt8]) -> CFDictionary {
    var attributes = item
    attributes[kSecValueData] = .data(value)
    return attributes
  }

  private func read() -> (OSStatus, [UInt8]?) {
    var query = item
    query[kSecReturnData] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query, &result)
    return (status, result?.data)
  }

  @Test func a_browser_without_the_apis_answers_not_available() async {
    WebSecurity.install(store: InMemorySecretStore(failure: .unavailable("Web Crypto is unavailable")))
    await #expect(throws: WebSecurityError.unavailable("Web Crypto is unavailable")) { try await WebSecurity.unlock() }
    #expect(SecItemAdd(adding([1]), nil) == errSecNotAvailable)
    #expect(read().0 == errSecNotAvailable)
  }

  @Test func a_failed_unlock_stays_locked_and_can_be_retried() async throws {
    let store = InMemorySecretStore(failure: .storage("blocked"))
    WebSecurity.install(store: store)
    await #expect(throws: WebSecurityError.storage("blocked")) { try await WebSecurity.unlock() }
    #expect(read().0 == errSecInteractionNotAllowed)
    store.fail(with: nil)
    try await WebSecurity.unlock()
    #expect(read().0 == errSecItemNotFound)
  }

  @Test func lock_forgets_the_plaintext_until_the_next_unlock() async throws {
    let store = InMemorySecretStore()
    WebSecurity.install(store: store)
    try await WebSecurity.unlock()
    #expect(SecItemAdd(adding([7]), nil) == errSecSuccess)

    await WebSecurity.lock()
    #expect(!WebSecurity.isUnlocked)
    #expect(read().0 == errSecInteractionNotAllowed)
    #expect(store.snapshot.count == 1, "the pending write finished before the lock")

    try await WebSecurity.unlock()
    #expect(read().1 == [7])
  }

  @Test func a_write_that_fails_is_reported_and_the_item_stays_in_memory() async throws {
    let store = InMemorySecretStore()
    WebSecurity.install(store: store)
    try await WebSecurity.unlock()
    store.fail(with: .storage("quota exceeded"))
    #expect(SecItemAdd(adding([3]), nil) == errSecSuccess)
    await WebSecurity.synchronize()
    #expect(WebSecurity.lastPersistenceError == .storage("quota exceeded"))
    #expect(read().1 == [3])
    #expect(store.snapshot.isEmpty)
  }

  @Test func each_tab_reads_the_store_when_it_unlocks() async throws {
    let store = InMemorySecretStore()
    let first = _SecKeychain(store: store)
    let second = _SecKeychain(store: store)
    try await first.unlock()
    try await second.unlock()
    #expect(first.add(adding([5])).0 == errSecSuccess)
    await first.synchronize()

    var query = item
    query[kSecReturnData] = true
    #expect(second.copyMatching(query).0 == errSecItemNotFound, "the second tab still has what it read")
    await second.lock()
    try await second.unlock()
    #expect(second.copyMatching(query).1?.data == [5])
  }
}
}
