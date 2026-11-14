import Testing
@testable import SwiftUIWebSecurity

/// The Security.framework-shaped item calls: Apple's status codes and result shapes, persistence of
/// every change to the store, and a refusal for what the browser cannot keep honestly.
extension GlobalKeychainSuites {
@Suite(.serialized)
struct SecItemTests {
  private let token: [UInt8] = Array("s3cret".utf8)

  private func unlocked(_ store: InMemorySecretStore = InMemorySecretStore()) async throws -> InMemorySecretStore {
    WebSecurity.install(store: store)
    try await WebSecurity.unlock()
    return store
  }

  private func item(_ account: String = "ana", data: [UInt8]? = nil) -> CFDictionary {
    var query: CFDictionary = [kSecClass: kSecClassGenericPassword, kSecAttrService: "studio", kSecAttrAccount: .string(account)]
    if let data { query[kSecValueData] = .data(data) }
    return query
  }

  @Test func calls_wait_for_the_unlock() async throws {
    WebSecurity.install(store: InMemorySecretStore())
    #expect(SecItemAdd(item(data: token), nil) == errSecInteractionNotAllowed)
    try await WebSecurity.unlock()
    #expect(WebSecurity.isUnlocked)
    #expect(SecItemAdd(item(data: token), nil) == errSecSuccess)
  }

  @Test func add_copy_update_delete_follow_apple_statuses() async throws {
    _ = try await unlocked()
    #expect(SecItemAdd(item(data: token), nil) == errSecSuccess)
    #expect(SecItemAdd(item(data: token), nil) == errSecDuplicateItem)

    var query = item()
    query[kSecReturnData] = kCFBooleanTrue!
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
    #expect(result?.data == token)

    #expect(SecItemUpdate(item(), [kSecValueData: .data([1, 2])]) == errSecSuccess)
    #expect(SecItemCopyMatching(query, &result) == errSecSuccess && result?.data == [1, 2])

    #expect(SecItemDelete(item()) == errSecSuccess)
    #expect(SecItemCopyMatching(query, &result) == errSecItemNotFound)
    #expect(SecItemDelete(item()) == errSecItemNotFound)
    #expect(SecItemUpdate(item(), [kSecAttrLabel: "x"]) == errSecItemNotFound)
  }

  /// The browser's store keeps at most a megabyte per item: more is refused at once, not accepted and lost on reload.
  @Test func an_item_the_store_cannot_keep_is_refused() async throws {
    _ = try await unlocked()
    let large = [UInt8](repeating: 7, count: 1_100_000)
    #expect(SecItemAdd(item("big", data: large), nil) == errSecAllocate)
    #expect(SecItemAdd(item("small", data: [1]), nil) == errSecSuccess)
    #expect(SecItemUpdate(item("small"), [kSecValueData: .data(large)]) == errSecAllocate)
    var result: CFTypeRef?
    var query = item("small")
    query[kSecReturnData] = kCFBooleanTrue!
    #expect(SecItemCopyMatching(query, &result) == errSecSuccess && result?.data == [1])
  }

  /// Security.framework compares a CFBoolean and a CFNumber by value: 0 finds an item stored with false.
  @Test func booleans_and_their_numbers_match_each_other() async throws {
    _ = try await unlocked()
    var stored = item("flagged", data: [1])
    stored[kSecAttrSynchronizable] = .int(0)
    #expect(SecItemAdd(stored, nil) == errSecSuccess)
    var query = item("flagged")
    query[kSecAttrSynchronizable] = kCFBooleanFalse!
    var result: CFTypeRef?
    #expect(SecItemCopyMatching(query, &result) == errSecSuccess)
    // 1 is true, as for an add: the browser keychain does not synchronize.
    query[kSecAttrSynchronizable] = .int(1)
    #expect(SecItemCopyMatching(query, &result) == errSecUnimplemented)
    query[kSecAttrSynchronizable] = nil
    query[kSecAttrLabel] = .int(0)
    #expect(SecItemCopyMatching(query, &result) == errSecItemNotFound)
  }

  /// A record whose lengths or integers do not fit is unreadable, not a trap (Int is 32 bits in the browser build).
  @Test func a_damaged_record_is_unreadable() {
    let record = _SecRecord(id: "1", attributes: [kSecClass: kSecClassGenericPassword, "n": .int(5)], value: [1, 2, 3])
    var bytes = record.encoded()
    #expect(_SecRecord.decode(id: "1", from: bytes)?.value == [1, 2, 3])
    // The value's length (the last four bytes before its three) says 0xffffffff.
    let at = bytes.count - 7
    for offset in 0 ..< 4 { bytes[at + offset] = 0xff }
    #expect(_SecRecord.decode(id: "1", from: bytes) == nil)
  }

  /// Stored ids are names: one near the end of Int (2^31 - 1 in the browser build) does not trap the next add, and a
  /// record this version cannot read keeps its id instead of being overwritten by a new item.
  @Test func stored_ids_never_trap_or_get_reused() async throws {
    let near = _SecRecord(id: "2147483646", attributes: [kSecClass: kSecClassGenericPassword, kSecAttrService: "studio", kSecAttrAccount: "old"], value: [1])
    let store = InMemorySecretStore(["2147483646": near.encoded(), "9": [0xde, 0xad]])
    _ = try await unlocked(store)
    #expect(SecItemAdd(item("first", data: [2]), nil) == errSecSuccess)
    #expect(SecItemAdd(item("second", data: [3]), nil) == errSecSuccess)
    await WebSecurity.synchronize()
    #expect(store.snapshot["9"] == [0xde, 0xad])
    #expect(store.snapshot.count == 4)
  }

  /// The two ids before Int's end are both stored: the next add takes neither, so neither record is overwritten.
  @Test func an_add_never_takes_a_stored_id_at_the_end_of_int() async throws {
    let last = String(Int.max - 1), beforeLast = String(Int.max - 2)
    let a = _SecRecord(id: beforeLast, attributes: [kSecClass: kSecClassGenericPassword, kSecAttrService: "studio", kSecAttrAccount: "a"], value: [1])
    let b = _SecRecord(id: last, attributes: [kSecClass: kSecClassGenericPassword, kSecAttrService: "studio", kSecAttrAccount: "b"], value: [2])
    let store = InMemorySecretStore([beforeLast: a.encoded(), last: b.encoded()])
    _ = try await unlocked(store)
    #expect(SecItemAdd(item("c", data: [3]), nil) == errSecSuccess)
    #expect(SecItemAdd(item("d", data: [4]), nil) == errSecSuccess)
    await WebSecurity.synchronize()
    #expect(store.snapshot[beforeLast] == a.encoded())
    #expect(store.snapshot[last] == b.encoded())
    #expect(store.snapshot.count == 4)
  }

  @Test func a_query_without_a_class_is_refused_and_changes_nothing() async throws {
    _ = try await unlocked()
    #expect(SecItemAdd(item("ana", data: [1]), nil) == errSecSuccess)
    var result: CFTypeRef?
    #expect(SecItemDelete([:]) == errSecParam)
    #expect(SecItemDelete([kSecAttrService: "studio"]) == errSecParam)
    #expect(SecItemCopyMatching([kSecReturnData: true], &result) == errSecParam)
    #expect(SecItemUpdate([kSecAttrAccount: "ana"], [kSecValueData: .data([9])]) == errSecParam)
    var query = item("ana")
    query[kSecReturnData] = kCFBooleanTrue!
    #expect(SecItemCopyMatching(query, &result) == errSecSuccess && result?.data == [1])
  }

  @Test func attributes_and_match_all_return_dictionaries() async throws {
    _ = try await unlocked()
    _ = SecItemAdd(item("ana", data: [1]), nil)
    _ = SecItemAdd(item("bia", data: [2]), nil)
    var result: CFTypeRef?
    let all: CFDictionary = [kSecClass: kSecClassGenericPassword, kSecAttrService: "studio",
                             kSecReturnAttributes: true, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitAll]
    #expect(SecItemCopyMatching(all, &result) == errSecSuccess)
    let accounts = Set(result?.items.compactMap { $0[kSecAttrAccount]?.stringValue } ?? [])
    #expect(accounts == ["ana", "bia"])
    #expect(result?.items.allSatisfy { $0[kSecValueData]?.dataValue != nil } == true)
    #expect(SecItemUpdate([kSecClass: kSecClassGenericPassword, kSecAttrAccount: "bia"], [kSecAttrAccount: "ana"]) == errSecDuplicateItem)
  }

  @Test func changes_reach_the_store_encoded_and_survive_a_new_unlock() async throws {
    let store = try await unlocked()
    _ = SecItemAdd(item(data: token), nil)
    await WebSecurity.synchronize()
    #expect(store.snapshot.count == 1)

    WebSecurity.install(store: store)
    try await WebSecurity.unlock()
    var result: CFTypeRef?
    var query = item()
    query[kSecReturnData] = true
    #expect(SecItemCopyMatching(query, &result) == errSecSuccess && result?.data == token)

    _ = SecItemDelete(item())
    await WebSecurity.synchronize()
    #expect(store.snapshot.isEmpty)
  }

  @Test func session_credentials_and_sync_are_refused() async throws {
    _ = try await unlocked()
    let session: CFDictionary = [kSecClass: kSecClassInternetPassword, kSecAttrServer: "api.example.com",
                                 kSecAttrAccount: "ana", kSecValueData: .data(token)]
    #expect(SecItemAdd(session, nil) == errSecUnimplemented)
    var result: CFTypeRef?
    #expect(SecItemCopyMatching([kSecClass: kSecClassInternetPassword], &result) == errSecUnimplemented)
    var synced = item(data: token)
    synced[kSecAttrSynchronizable] = true
    #expect(SecItemAdd(synced, nil) == errSecUnimplemented)
    #expect(SecItemAdd([kSecClass: kSecClassGenericPassword], nil) == errSecParam, "no value data")
    #expect(SecCopyErrorMessageString(errSecUnimplemented, nil)?.contains("HttpOnly") == true)
  }

  @Test func records_round_trip_and_reject_damage() {
    let record = _SecRecord(id: "7", attributes: [kSecClass: kSecClassGenericPassword, kSecAttrAccount: "ana",
                                                   kSecAttrGeneric: .data([9]), kSecAttrSynchronizable: false], value: token)
    let bytes = record.encoded()
    #expect(_SecRecord.decode(id: "7", from: bytes) == record)
    #expect(_SecRecord.decode(id: "7", from: Array(bytes.dropLast())) == nil)
    #expect(!String(decoding: bytes, as: UTF8.self).isEmpty)
  }
}
}
