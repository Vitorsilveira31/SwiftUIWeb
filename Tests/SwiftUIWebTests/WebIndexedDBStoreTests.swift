import Foundation
import Testing
import SwiftUIWebBrowser

/// The native IndexedDB fallback is the deterministic stand-in used by tests
/// and native tooling. Each test uses its own database name because the
/// fallback is one process-wide dictionary, like the browser's origin store.
@Suite(.processGlobalState)
@MainActor
final class WebIndexedDBStoreTests {
  private struct Draft: Codable, Equatable {
    var title: String
  }

  /// A record whose keys match an envelope, used to read an envelope written
  /// for another value type as an unversioned (version 0) payload.
  private struct Unversioned: Codable, Equatable {
    var version: Int
    var value: String
  }

  private enum EncodingFailure: Error { case refused }

  private struct Refusing: Codable, Equatable {
    var typed: Bool
    func encode(to encoder: Encoder) throws {
      if typed { throw WebIndexedDBError.database("refused by the value") }
      throw EncodingFailure.refused
    }
  }

  private func error(_ body: () async throws -> Void) async -> WebIndexedDBError? {
    do {
      try await body()
      return nil
    } catch let error as WebIndexedDBError {
      return error
    } catch {
      return .database("unexpected \(error)")
    }
  }

  @Test
  func errorsDescribeTheirCause() {
    #expect(WebIndexedDBError.unavailable.description == "IndexedDB is unavailable on this host")
    #expect(WebIndexedDBError.cancelled.description == "IndexedDB operation was cancelled")
    #expect(WebIndexedDBError.invalidKey.description == "IndexedDB keys must be non-empty and at most 1024 bytes")
    #expect(WebIndexedDBError.quotaExceeded.description == "IndexedDB storage quota was exceeded")
    #expect(WebIndexedDBError.incompatibleVersion(found: 3, expected: 2).description
      == "IndexedDB record version 3 is newer than supported version 2")
    #expect(WebIndexedDBError.migrationRequired(from: 1, to: 4).description
      == "No IndexedDB migration is registered from version 1 to 4")
    #expect(WebIndexedDBError.encoding("bad").description == "IndexedDB encoding failed: bad")
    #expect(WebIndexedDBError.database("closed").description == "IndexedDB error: closed")
  }

  @Test
  func keyedAliasesRoundTripAndDeleteRecords() async throws {
    let store = WebIndexedDB<Draft>(databaseName: "indexeddb-aliases")
    #expect(store.objectStoreName == "records")
    #expect(store.quotaBytes == nil)
    #expect(try await store.value(forKey: "draft") == nil)
    try await store.setValue(Draft(title: "One"), forKey: "draft")
    #expect(try await store.value(forKey: "draft") == Draft(title: "One"))
    try await store.removeValue(forKey: "draft")
    #expect(try await store.load(key: "draft") == nil)

    // Object stores are separate namespaces inside one database.
    let other = WebIndexedDB<Draft>(databaseName: "indexeddb-aliases", objectStoreName: "archive")
    try await store.save(Draft(title: "Live"), key: "shared")
    #expect(try await other.load(key: "shared") == nil)
  }

  @Test
  func keysMustBeNonEmptyAndBounded() async throws {
    let store = WebIndexedDB<Draft>(databaseName: "indexeddb-keys")
    let long = String(repeating: "k", count: 1025)
    #expect(await error { _ = try await store.load(key: "") } == .invalidKey)
    #expect(await error { try await store.save(Draft(title: "x"), key: long) } == .invalidKey)
    #expect(await error { try await store.delete(key: "") } == .invalidKey)
    #expect(await error { try await store.transaction([(key: "ok", value: Draft(title: "a")), (key: "", value: nil)]) } == .invalidKey)
    #expect(try await store.load(key: "ok") == nil, "an invalid key rejects the whole batch")
    #expect(await error { try await store.save(Draft(title: "max"), key: String(repeating: "k", count: 1024)) } == nil)
  }

  @Test
  func newerRecordsAndMissingMigrationsAreRejected() async throws {
    let newer = WebIndexedDB<Draft>(databaseName: "indexeddb-versions", version: 3)
    try await newer.save(Draft(title: "From the future"), key: "draft")
    let older = WebIndexedDB<Draft>(databaseName: "indexeddb-versions", version: 2)
    #expect(await error { _ = try await older.load(key: "draft") } == .incompatibleVersion(found: 3, expected: 2))

    let v1 = WebIndexedDB<Draft>(databaseName: "indexeddb-chain", version: 1)
    try await v1.save(Draft(title: "v1"), key: "draft")
    let gap = WebIndexedDB<Draft>(
      databaseName: "indexeddb-chain",
      version: 3,
      migrations: [.init(fromVersion: 1, toVersion: 2) { Draft(title: $0.title + "+2") }]
    )
    #expect(await error { _ = try await gap.load(key: "draft") } == .migrationRequired(from: 2, to: 3))
    // A migration that overshoots the store's version is not applied.
    let overshoot = WebIndexedDB<Draft>(
      databaseName: "indexeddb-chain",
      version: 2,
      migrations: [.init(fromVersion: 1, toVersion: 3) { $0 }]
    )
    #expect(await error { _ = try await overshoot.load(key: "draft") } == .migrationRequired(from: 1, to: 2))
    // Chained migrations run in order regardless of registration order.
    let chained = WebIndexedDB<Draft>(
      databaseName: "indexeddb-chain",
      version: 3,
      migrations: [
        .init(fromVersion: 2, toVersion: 3) { Draft(title: $0.title + "+3") },
        .init(fromVersion: 1, toVersion: 2) { Draft(title: $0.title + "+2") },
      ]
    )
    #expect(try await chained.load(key: "draft") == Draft(title: "v1+2+3"))
    #expect(try await WebIndexedDB<Draft>(databaseName: "indexeddb-chain", version: 3).load(key: "draft")
      == Draft(title: "v1+2+3"), "the migrated record was rewritten at the current version")
  }

  @Test
  func unversionedRecordsAreAdoptedOrMigratedFromVersionZero() async throws {
    // An envelope holding a String does not decode as an envelope of
    // `Unversioned`, so the store reads it as an unversioned payload.
    let writer = WebIndexedDB<String>(databaseName: "indexeddb-legacy", version: 1)
    try await writer.save("legacy", key: "adopted")
    try await writer.save("legacy", key: "migrated")
    try await writer.save("legacy", key: "blocked")

    let adopting = WebIndexedDB<Unversioned>(databaseName: "indexeddb-legacy", version: 1)
    #expect(try await adopting.load(key: "adopted") == Unversioned(version: 1, value: "legacy"))

    let blocked = WebIndexedDB<Unversioned>(databaseName: "indexeddb-legacy", version: 2)
    #expect(await error { _ = try await blocked.load(key: "blocked") } == .migrationRequired(from: 0, to: 2))

    let migrating = WebIndexedDB<Unversioned>(
      databaseName: "indexeddb-legacy",
      version: 2,
      migrations: [.init(fromVersion: 0, toVersion: 2) { Unversioned(version: 2, value: $0.value.uppercased()) }]
    )
    #expect(try await migrating.load(key: "migrated") == Unversioned(version: 2, value: "LEGACY"))
    // The upgrade is durable: the record is now a version 2 envelope.
    #expect(try await WebIndexedDB<Unversioned>(databaseName: "indexeddb-legacy", version: 2).load(key: "migrated")
      == Unversioned(version: 2, value: "LEGACY"))

    // A payload that matches neither shape is an encoding failure.
    let mismatched = WebIndexedDB<Int>(databaseName: "indexeddb-legacy", version: 1)
    #expect(await error { _ = try await mismatched.load(key: "blocked") } == .encoding("Storage encoding failed"))
  }

  @Test
  func encodingFailuresKeepTheirTypeAndLeaveStorageUntouched() async throws {
    let store = WebIndexedDB<Refusing>(databaseName: "indexeddb-encoding")
    #expect(await error { try await store.save(Refusing(typed: false), key: "a") } == .encoding("Storage encoding failed"))
    #expect(await error { try await store.save(Refusing(typed: true), key: "a") } == .database("refused by the value"))
    #expect(await error { try await store.transaction([(key: "a", value: Refusing(typed: false))]) }
      == .encoding("Storage encoding failed"))
    #expect(await error { try await store.transaction([(key: "a", value: Refusing(typed: true))]) }
      == .database("refused by the value"))
  }

  @Test
  func quotaCountsTheWholeStoreAndRejectsWritesAtomically() async throws {
    let store = WebIndexedDB<String>(databaseName: "indexeddb-quota", quotaBytes: 64)
    #expect(store.quotaBytes == 64)
    try await store.save("small", key: "a")
    #expect(await error { try await store.save(String(repeating: "x", count: 80), key: "b") } == .quotaExceeded)
    #expect(try await store.load(key: "b") == nil)

    // One oversized value fails the batch before anything is written.
    #expect(await error {
      try await store.transaction([(key: "c", value: "ok"), (key: "d", value: String(repeating: "y", count: 80))])
    } == .quotaExceeded)
    #expect(try await store.load(key: "c") == nil)

    // Values that each fit next to "a" but not together are rejected as a unit.
    #expect(await error {
      try await store.transaction([(key: "c", value: String(repeating: "c", count: 10)), (key: "d", value: String(repeating: "d", count: 10))])
    } == .quotaExceeded)
    #expect(try await store.load(key: "c") == nil)

    // Deleting a record in the same batch frees its bytes for the new value.
    try await store.transaction([(key: "a", value: nil), (key: "c", value: String(repeating: "c", count: 20))])
    #expect(try await store.load(key: "a") == nil)
    #expect(try await store.load(key: "c") == String(repeating: "c", count: 20))
  }

  @Test
  func transactionsApplyWritesAndDeletionsTogether() async throws {
    let store = WebIndexedDB<Draft>(databaseName: "indexeddb-transaction")
    try await store.save(Draft(title: "old"), key: "removed")
    try await store.transaction([
      (key: "first", value: Draft(title: "1")),
      (key: "removed", value: nil),
      (key: "first", value: Draft(title: "1b")),
    ])
    #expect(try await store.load(key: "first") == Draft(title: "1b"))
    #expect(try await store.load(key: "removed") == nil)
    try await store.transaction([])
    #expect(try await store.load(key: "first") == Draft(title: "1b"))
  }
}
