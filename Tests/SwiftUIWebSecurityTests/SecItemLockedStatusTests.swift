import Testing
@testable import SwiftUIWebSecurity

/// Every one of the four calls answers the same status in each state without the items in memory,
/// and a `lock()` that overtakes a loading `unlock()` keeps the store locked.
extension GlobalKeychainSuites {
@Suite(.serialized)
struct SecItemLockedStatusTests {
  private let item: CFDictionary = [kSecClass: kSecClassGenericPassword, kSecAttrService: "studio", kSecAttrAccount: "ana"]

  /// Add, CopyMatching, Update and Delete, in that order, on valid dictionaries.
  private func allFour() -> [OSStatus] {
    var attributes = item
    attributes[kSecValueData] = .data([1, 2, 3])
    var query = item
    query[kSecReturnData] = true
    var result: CFTypeRef?
    return [
      SecItemAdd(attributes, nil),
      SecItemCopyMatching(query, &result),
      SecItemUpdate(item, [kSecValueData: .data([4])]),
      SecItemDelete(item),
    ]
  }

  private func storedItem() -> (id: String, value: [UInt8]) {
    var attributes = item
    attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
    return (id: "1", value: _SecRecord(id: "1", attributes: attributes, value: [9]).encoded())
  }

  @Test func before_unlock_all_four_answer_interaction_not_allowed() {
    WebSecurity.install(store: InMemorySecretStore())
    #expect(allFour() == Array(repeating: errSecInteractionNotAllowed, count: 4))
  }

  @Test func without_indexeddb_or_web_crypto_all_four_answer_not_available() async {
    WebSecurity.install(store: InMemorySecretStore(failure: .unavailable("no Web Crypto")))
    _ = try? await WebSecurity.unlock()
    #expect(allFour() == Array(repeating: errSecNotAvailable, count: 4))
  }

  @Test func after_a_failed_unlock_all_four_answer_interaction_not_allowed() async {
    WebSecurity.install(store: InMemorySecretStore(failure: .storage("blocked")))
    _ = try? await WebSecurity.unlock()
    #expect(allFour() == Array(repeating: errSecInteractionNotAllowed, count: 4))
  }

  @Test func after_lock_all_four_answer_interaction_not_allowed() async throws {
    let store = InMemorySecretStore()
    WebSecurity.install(store: store)
    try await WebSecurity.unlock()
    #expect(allFour() == [errSecSuccess, errSecSuccess, errSecSuccess, errSecSuccess], "unlocked, the same calls succeed")
    await WebSecurity.lock()
    #expect(allFour() == Array(repeating: errSecInteractionNotAllowed, count: 4))
  }

  @Test func a_lock_during_an_unlock_keeps_the_store_locked() async throws {
    let store = GatedSecretStore(items: [storedItem()])
    WebSecurity.install(store: store)

    // unlock starts, and its load is in flight.
    let overtaken = Task { try await WebSecurity.unlock() }
    try #require(await store.untilWaiting(1), "the unlock's load is in flight")

    // lock is called and returns before the load finishes.
    await WebSecurity.lock()
    #expect(!WebSecurity.isUnlocked)

    // The old load finishes; it must change nothing.
    await store.open()
    try await overtaken.value
    #expect(!WebSecurity.isUnlocked)
    #expect(allFour() == Array(repeating: errSecInteractionNotAllowed, count: 4))

    // Only an unlock called after the lock unlocks again, with a load of its own.
    let fresh = Task { try await WebSecurity.unlock() }
    try #require(await store.untilWaiting(1), "the unlock's load is in flight")
    await store.open()
    try await fresh.value
    #expect(WebSecurity.isUnlocked)
    #expect(await store.loads == 2)
    var query = item
    query[kSecReturnData] = true
    var result: CFTypeRef?
    #expect(SecItemCopyMatching(query, &result) == errSecSuccess && result?.data == [9])
  }

  @Test func a_failing_unlock_overtaken_by_lock_does_not_mark_the_store_unavailable() async throws {
    let store = GatedSecretStore(failure: .unavailable("no Web Crypto"))
    WebSecurity.install(store: store)
    let overtaken = Task { try await WebSecurity.unlock() }
    try #require(await store.untilWaiting(1), "the unlock's load is in flight")
    await WebSecurity.lock()
    await store.open()
    _ = try? await overtaken.value
    #expect(allFour() == Array(repeating: errSecInteractionNotAllowed, count: 4))
  }
}
}
