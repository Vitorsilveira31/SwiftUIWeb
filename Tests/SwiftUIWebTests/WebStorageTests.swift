import Testing
import Foundation
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(StorageTesting) import SwiftUIWebCore
@_spi(StorageTesting) import SwiftUIWebFeatures
import SwiftUIWebBrowser

@Suite(.serialized, .processGlobalState)
@MainActor
final class WebStorageTests {
  deinit {
    StorageRuntime.install(nil)
  }

  @Test
  func testAppStorageReadsThroughAdapterOnceAndInvalidates() {
    var values: [String: String] = ["name": "Ada"]
    var reads = 0
    StorageRuntime.install(StorageAdapter(
      read: { key in reads += 1; return values[key] },
      write: { values[$0] = $1 }
    ))

    let first = AppStorage(wrappedValue: "", "name")
    _expectEqual(first.wrappedValue, "Ada")
    let second = AppStorage(wrappedValue: "", "name")
    _expectEqual(second.wrappedValue, "Ada")
    _expectEqual(reads, 1)

    values["name"] = "Grace"
    _expectEqual(second.wrappedValue, "Ada", "cached values remain stable until a host invalidates them")
    StorageRuntime.invalidateCache(scope: .app, key: "name")
    _expectEqual(second.wrappedValue, "Grace")
    _expectEqual(reads, 2)
  }

  @Test
  func testAppAndSceneStorageUseSeparateNamespaces() {
    var appValues: [String: String] = [:]
    var sceneValues: [String: String] = [:]
    StorageRuntime.install(
      appAdapter: StorageAdapter(read: { appValues[$0] }, write: { appValues[$0] = $1 }),
      sceneAdapter: StorageAdapter(read: { sceneValues[$0] }, write: { sceneValues[$0] = $1 })
    )

    let app = AppStorage(wrappedValue: "default", "selection")
    let scene = SceneStorage(wrappedValue: "default", "selection")
    app.wrappedValue = "app"
    scene.wrappedValue = "scene"
    _expectEqual(appValues["selection"], "app")
    _expectEqual(sceneValues["selection"], "scene")
    _expectEqual(AppStorage(wrappedValue: "default", "selection").wrappedValue, "app")
    _expectEqual(SceneStorage(wrappedValue: "default", "selection").wrappedValue, "scene")

    // The compatibility overload still keeps one adapter usable for both
    // wrappers, but scopes the scene key so the values cannot collide.
    var shared: [String: String] = [:]
    StorageRuntime.install(StorageAdapter(read: { shared[$0] }, write: { shared[$0] = $1 }))
    let sharedApp = AppStorage(wrappedValue: "", "same")
    let sharedScene = SceneStorage(wrappedValue: "", "same")
    sharedApp.wrappedValue = "app"
    sharedScene.wrappedValue = "scene"
    _expectEqual(shared["same"], "app")
    _expectEqual(shared["__SwiftUIWeb.SceneStorage.same"], "scene")
  }

  @Test
  func testCommonSwiftUIAppStorageScalarAndFoundationValuesRoundTrip() {
    var values: [String: String] = [:]
    StorageRuntime.install(StorageAdapter(
      read: { values[$0] }, write: { values[$0] = $1 }
    ))
    let float = AppStorage(wrappedValue: Float.zero, "float")
    let url = AppStorage(wrappedValue: URL(string: "https://example.com")!, "url")
    let data = AppStorage(wrappedValue: Data([1, 2, 3]), "data")
    float.wrappedValue = 1.5
    url.wrappedValue = URL(string: "https://swift.org")!
    data.wrappedValue = Data([9, 8, 7])
    _expectEqual(AppStorage(wrappedValue: Float.zero, "float").wrappedValue, 1.5)
    _expectEqual(AppStorage(wrappedValue: URL(string: "https://example.com")!, "url").wrappedValue.absoluteString, "https://swift.org")
    _expectEqual(AppStorage(wrappedValue: Data(), "data").wrappedValue, Data([9, 8, 7]))
  }

  @Test
  func testReloadAndSecondSessionObservePersistedScalarValues() {
    var sharedLocalStorage: [String: String] = [:]
    var firstSessionValues: [String: String] = [:]
    var secondSessionValues: [String: String] = [:]
    let firstSession = StorageAdapter(
      read: { sharedLocalStorage[$0] }, write: { sharedLocalStorage[$0] = $1 })
    StorageRuntime.install(
      appAdapter: firstSession,
      sceneAdapter: StorageAdapter(
        read: { firstSessionValues[$0] }, write: { firstSessionValues[$0] = $1 }
      )
    )
    let value = AppStorage(wrappedValue: 0, "launchCount")
    let sceneValue = SceneStorage(wrappedValue: "default", "tab")
    value.wrappedValue = 3
    sceneValue.wrappedValue = "first-tab"
    StorageRuntime.flush()

    // A new BrowserSession installs a fresh adapter and starts with an empty
    // Swift cache, while the shared localStorage survives the reload.
    let secondSession = StorageAdapter(
      read: { sharedLocalStorage[$0] }, write: { sharedLocalStorage[$0] = $1 })
    StorageRuntime.install(
      appAdapter: secondSession,
      sceneAdapter: StorageAdapter(
        read: { secondSessionValues[$0] }, write: { secondSessionValues[$0] = $1 }
      )
    )
    _expectEqual(AppStorage(wrappedValue: 0, "launchCount").wrappedValue, 3)
    _expectEqual(SceneStorage(wrappedValue: "default", "tab").wrappedValue, "default")
  }

  @Test
  func testIndexedDBMigrationIsVersionedAndDurable() async throws {
    struct Draft: Codable, Equatable {
      var title: String
      var body: String
    }

    let oldStore = WebIndexedDB<Draft>(databaseName: "web-storage-tests", version: 1)
    try await oldStore.save(Draft(title: "Old", body: "Text"), key: "draft")
    let newStore = WebIndexedDB<Draft>(
      databaseName: "web-storage-tests",
      version: 2,
      migrations: [
        .init(fromVersion: 1, toVersion: 2) { old in
          Draft(title: old.title, body: old.body + " migrated")
        }
      ]
    )

    let migrated = try await newStore.load(key: "draft")
    _expectEqual(migrated, Draft(title: "Old", body: "Text migrated"))
    // The migrated envelope is persisted; a second read does not run the
    // migration again and remains identical after a simulated reload.
    let reloaded = try await newStore.load(key: "draft")
    _expectEqual(reloaded, Draft(title: "Old", body: "Text migrated"))
  }

  @Test
  func testStorageTransactionRevisionConflictAndReload() throws {
    var values: [String: String] = ["old": "value"]
    var reads = 0
    StorageRuntime.install(StorageAdapter(
      read: { key in reads += 1; return values[key] },
      write: { values[$0] = $1 },
      remove: { values.removeValue(forKey: $0) },
      quotaBytes: 64
    ))
    let initial = StorageRuntime.revision()
    let committed = try StorageRuntime.transaction([
      .set(key: "new", value: "value"), .remove(key: "old")
    ], expectedRevision: initial)
    _expectEqual(committed, initial + 2)
    _expectEqual(values["new"], "value")
    _expectNil(values["old"])
    _expectThrows(try StorageRuntime.transaction(
      [.set(key: "stale", value: "write")], expectedRevision: initial
    )) { error in
      _expectEqual(error as? StorageError, .transactionConflict(expected: initial, actual: committed))
    }

    let cached = AppStorage(wrappedValue: "default", "new")
    _expectEqual(cached.wrappedValue, "value")
    values["new"] = "reloaded"
    _expectEqual(cached.wrappedValue, "value")
    StorageRuntime.reload()
    _expectEqual(cached.wrappedValue, "reloaded")
    _expectEqual(reads, 1)
  }

  @Test
  func testStorageTransactionRejectsQuotaBeforeWriting() {
    var values: [String: String] = [:]
    StorageRuntime.install(StorageAdapter(
      read: { values[$0] }, write: { values[$0] = $1 }, quotaBytes: 4
    ))
    _expectThrows(try StorageRuntime.transaction([.set(key: "long", value: "value")])) { error in
      _expectEqual(error as? StorageError, .quotaExceeded)
    }
    _expectTrue(values.isEmpty)
  }

  @Test
  func testFailedThrowingWriteDoesNotAdvanceRevisionOrCache() {
    var writes = 0
    StorageRuntime.install(StorageAdapter(
      read: { _ in nil },
      write: { _, _ in writes += 1 },
      throwingWrite: { _, _ in throw StorageError.quotaExceeded }
    ))
    let value = AppStorage(wrappedValue: "default", "quota")
    value.wrappedValue = "rejected"
    _expectEqual(writes, 0, "the throwing host path supersedes the compatibility closure")
    _expectEqual(StorageRuntime.revision(), 0)
    _expectEqual(StorageRuntime.lastError, .quotaExceeded)
    _expectEqual(value.wrappedValue, "default")
  }

  @Test
  func testReloadRefreshesHostRevisionBeforeTheNextTransaction() throws {
    var hostRevision: UInt64 = 4
    var values: [String: String] = [:]
    StorageRuntime.install(StorageAdapter(
      read: { values[$0] },
      write: { values[$0] = $1 },
      revision: { hostRevision }
    ))
    _expectEqual(StorageRuntime.revision(), 4)
    hostRevision = 7
    StorageRuntime.reload()
    _expectEqual(StorageRuntime.revision(), 7)
    _expectEqual(try StorageRuntime.transaction([.set(key: "key", value: "value")], expectedRevision: 7), 8)
  }

  @Test
  func testStorageRejectsUnavailableInvalidKeysAndExhaustedRevisions() throws {
    StorageRuntime.install(nil)
    _expectNil(StorageRuntime.read("", scope: .app))
    _expectEqual(StorageRuntime.lastError, .invalidKey)
    _expectThrows(try StorageRuntime.transaction([.set(key: "key", value: "value")])) { error in
      _expectEqual(error as? StorageError, .unavailable)
    }

    var values: [String: String] = [:]
    StorageRuntime.install(StorageAdapter(
      read: { values[$0] },
      write: { values[$0] = $1 },
      revision: { UInt64.max }
    ))
    StorageRuntime.write("value", forKey: "")
    _expectEqual(StorageRuntime.lastError, .invalidKey)
    StorageRuntime.write("value", forKey: "key")
    _expectEqual(StorageRuntime.lastError, .revisionExhausted)
    _expectThrows(try StorageRuntime.transaction([])) { error in
      _expectEqual(error as? StorageError, .revisionExhausted)
    }
    _expectTrue(values.isEmpty)
  }

  @Test
  func testHostTransactionReceivesNamespacedMutationsAndFlushes() throws {
    var applied: [StorageMutation] = []
    var flushes = 0
    var values: [String: String] = ["gone": "old"]
    StorageRuntime.install(StorageAdapter(
      read: { values[$0] },
      write: { values[$0] = $1 },
      remove: { values.removeValue(forKey: $0) },
      flush: { flushes += 1 },
      transaction: { mutations, expected in
        _expectEqual(expected, 10)
        applied = mutations
        return 11
      },
      revision: { 10 }
    ))

    let revision = try StorageRuntime.transaction(
      [.set(key: "new", value: "value"), .remove(key: "gone")],
      expectedRevision: 10
    )
    _expectEqual(revision, 11)
    _expectEqual(applied, [
      .set(key: "new", value: "value"),
      .remove(key: "gone")
    ])
    _expectEqual(StorageRuntime.read("new"), "value")
    _expectNil(StorageRuntime.read("gone"))

    StorageRuntime.flush()
    _expectEqual(flushes, 1)
  }

  @Test
  func testStorageScalarCodecCoversIntegerUnsignedAndBooleanSpellings() {
    var values: [String: String] = [:]
    StorageRuntime.install(StorageAdapter(
      read: { values[$0] }, write: { values[$0] = $1 }
    ))

    let signed = AppStorage(wrappedValue: Int8.zero, "signed")
    let unsigned = AppStorage(wrappedValue: UInt64.zero, "unsigned")
    let truth = AppStorage(wrappedValue: false, "truth")
    signed.wrappedValue = -8
    unsigned.wrappedValue = 42
    truth.wrappedValue = true
    _expectEqual(AppStorage(wrappedValue: Int8.zero, "signed").wrappedValue, -8)
    _expectEqual(AppStorage(wrappedValue: UInt64.zero, "unsigned").wrappedValue, 42)
    _expectEqual(AppStorage(wrappedValue: false, "truth").wrappedValue, true)

    values["truth"] = "yes"
    StorageRuntime.invalidateCache(scope: .app, key: "truth")
    _expectEqual(AppStorage(wrappedValue: false, "truth").wrappedValue, true)
    values["truth"] = "maybe"
    StorageRuntime.invalidateCache(scope: .app, key: "truth")
    _expectEqual(AppStorage(wrappedValue: false, "truth").wrappedValue, false)
  }

  @Test
  func testStorageHostFailuresAreTypedAndBackwardRevisionsAreRejected() throws {
    StorageRuntime.install(StorageAdapter(
      read: { _ in nil },
      write: { _, _ in },
      transaction: { _, _ in 0 },
      revision: { 1 }
    ))
    _expectThrows(try StorageRuntime.transaction([.set(key: "key", value: "value")])) { error in
      _expectEqual(error as? StorageError, .host("Storage adapter returned a backwards revision"))
    }

    StorageRuntime.install(StorageAdapter(
      read: { _ in nil },
      write: { _, _ in },
      transaction: { _, _ in throw NSError(domain: "StorageTests", code: 1) }
    ))
    _expectThrows(try StorageRuntime.transaction([.set(key: "key", value: "value")])) { error in
      _expectEqual(error as? StorageError, .host("Storage host operation failed"))
    }

    StorageRuntime.install(StorageAdapter(
      read: { _ in nil },
      write: { _, _ in },
      throwingWrite: { _, _ in throw NSError(domain: "StorageTests", code: 2) }
    ))
    let value = AppStorage(wrappedValue: "default", "key")
    value.wrappedValue = "rejected"
    _expectEqual(StorageRuntime.lastError, .host("Storage host operation failed"))
    _expectEqual(value.wrappedValue, "default")
  }

  @Test
  func testStorageErrorsExposeStableUserFacingDescriptions() {
    _expectEqual(StorageError.unavailable.description, "Storage is unavailable on this host")
    _expectEqual(StorageError.quotaExceeded.description, "Storage quota was exceeded")
    _expectEqual(
      StorageError.transactionConflict(expected: 2, actual: 5).description,
      "Storage transaction expected revision 2, found 5"
    )
    _expectEqual(StorageError.revisionExhausted.description, "Storage revision counter is exhausted")
    _expectEqual(StorageError.invalidKey.description, "Storage keys must not be empty")
    _expectEqual(StorageError.host("denied").description, "denied")
  }

  @Test
  func testScopedAdapterInstallationPreservesTheOtherScope() {
    var appValues: [String: String] = [:]
    var sceneValues: [String: String] = [:]
    var replacementAppValues: [String: String] = [:]
    var replacementSceneValues: [String: String] = [:]
    let originalApp = StorageAdapter(read: { appValues[$0] }, write: { appValues[$0] = $1 })
    let originalScene = StorageAdapter(read: { sceneValues[$0] }, write: { sceneValues[$0] = $1 })
    let replacementApp = StorageAdapter(
      read: { replacementAppValues[$0] }, write: { replacementAppValues[$0] = $1 }
    )
    let replacementScene = StorageAdapter(
      read: { replacementSceneValues[$0] }, write: { replacementSceneValues[$0] = $1 }
    )
    StorageRuntime.install(appAdapter: originalApp, sceneAdapter: originalScene)

    StorageRuntime.install(replacementApp, for: .app)
    AppStorage(wrappedValue: "", "selection").wrappedValue = "app"
    SceneStorage(wrappedValue: "", "selection").wrappedValue = "scene"
    _expectEqual(replacementAppValues["selection"], "app")
    _expectEqual(sceneValues["selection"], "scene")

    StorageRuntime.install(replacementScene, for: .scene)
    AppStorage(wrappedValue: "", "other").wrappedValue = "still-app"
    SceneStorage(wrappedValue: "", "other").wrappedValue = "new-scene"
    _expectEqual(replacementAppValues["other"], "still-app")
    _expectEqual(replacementSceneValues["other"], "new-scene")
    _expectTrue(StorageRuntime.hasAdapter(for: .app))
    _expectTrue(StorageRuntime.hasAdapter(for: .scene))
  }

  @Test
  func testWriteQuotaCountsUTF8BytesAndRejectsWithoutChangingRevision() {
    var values: [String: String] = [:]
    var writes = 0
    StorageRuntime.install(StorageAdapter(
      read: { values[$0] },
      write: { values[$0] = $1; writes += 1 },
      quotaBytes: 3
    ))
    let initialRevision = StorageRuntime.revision()

    StorageRuntime.write("a", forKey: "é")
    _expectEqual(values["é"], "a", "the two-byte key and one-byte value fit exactly")
    _expectEqual(StorageRuntime.revision(), initialRevision + 1)
    let committedRevision = StorageRuntime.revision()

    StorageRuntime.write("éé", forKey: "a")
    _expectEqual(values["a"], nil)
    _expectEqual(writes, 1)
    _expectEqual(StorageRuntime.revision(), committedRevision)
    _expectEqual(StorageRuntime.lastError, .quotaExceeded)
  }

  @Test
  func testTypedTransactionFailuresAndKeyOnlyInvalidationRefreshBothRevisions() throws {
    StorageRuntime.install(StorageAdapter(
      read: { _ in nil },
      write: { _, _ in },
      transaction: { _, _ in
        throw StorageError.transactionConflict(expected: 1, actual: 3)
      }
    ))
    _expectThrows(try StorageRuntime.transaction([.set(key: "key", value: "value")])) { error in
      _expectEqual(error as? StorageError, .transactionConflict(expected: 1, actual: 3))
    }
    _expectEqual(StorageRuntime.lastError, .transactionConflict(expected: 1, actual: 3))

    var appRevision: UInt64 = 4
    var sceneRevision: UInt64 = 7
    StorageRuntime.install(
      appAdapter: StorageAdapter(
        read: { _ in nil }, write: { _, _ in }, revision: { appRevision }
      ),
      sceneAdapter: StorageAdapter(
        read: { _ in nil }, write: { _, _ in }, revision: { sceneRevision }
      )
    )
    appRevision = 9
    sceneRevision = 12
    StorageRuntime.invalidateCache(key: "external-change")
    _expectEqual(StorageRuntime.revision(for: .app), 9)
    _expectEqual(StorageRuntime.revision(for: .scene), 12)
  }

  @Test
  func testFallbackTransactionPreservesTypedErrorsAndWrapsHostFailures() {
    StorageRuntime.install(StorageAdapter(
      read: { _ in nil },
      write: { _, _ in },
      throwingWrite: { _, _ in throw StorageError.quotaExceeded }
    ))
    _expectThrows(try StorageRuntime.transaction([.set(key: "item", value: "large")])) { error in
      _expectEqual(error as? StorageError, .quotaExceeded)
    }
    _expectEqual(StorageRuntime.lastError, .quotaExceeded)
    _expectEqual(StorageRuntime.revision(), 0)
    _expectNil(StorageRuntime.read("item"), "a failed transaction must not publish a cached value")

    StorageRuntime.install(StorageAdapter(
      read: { _ in nil },
      write: { _, _ in },
      throwingWrite: { _, _ in throw NSError(domain: "StorageTests", code: 3) }
    ))
    _expectThrows(try StorageRuntime.transaction([.set(key: "item", value: "failed")])) { error in
      _expectEqual(error as? StorageError, .host("Storage host operation failed"))
    }
    _expectEqual(StorageRuntime.lastError, .host("Storage host operation failed"))
    _expectEqual(StorageRuntime.revision(), 0)
    _expectNil(StorageRuntime.read("item"))
  }

  @Test
  func testEmbeddedStorageCodecRejectsValuesOutsideItsScalarContract() {
    struct UnsupportedValue: Equatable {}
    let unsupported = UnsupportedValue()

    _expectEqual(_encodeStorageValue(unsupported), nil)
    _expectEqual(_decodeStorageValue("opaque", as: UnsupportedValue.self), nil)
  }

  /// The runtime is process-global and native hosts reach it from several
  /// threads: an install on one while views read and write on others. Every
  /// entry point takes the runtime lock, so concurrent use neither corrupts
  /// the cache nor loses a write made after the last install.
  @Test(.timeLimit(.minutes(1)))
  func concurrentInstallsReadsAndWritesStayConsistent() async {
    final class Store: @unchecked Sendable {
      let lock = NSLock()
      var values: [String: String] = [:]
    }
    let store = Store()
    nonisolated(unsafe) let adapter = StorageAdapter(
      read: { key in store.lock.withLock { store.values[key] } },
      write: { key, value in store.lock.withLock { store.values[key] = value } })
    StorageRuntime.install(adapter)
    await withTaskGroup(of: Void.self) { group in
      for worker in 0..<8 {
        group.addTask {
          for iteration in 0..<400 {
            switch iteration % 4 {
            case 0: StorageRuntime.write("\(worker)-\(iteration)", forKey: "key-\(worker)")
            case 1: _ = StorageRuntime.read("key-\(worker)")
            case 2: _ = try? StorageRuntime.transaction([.set(key: "batch-\(worker)", value: "\(iteration)")])
            default: StorageRuntime.install(adapter)
            }
          }
        }
      }
    }
    StorageRuntime.write("final", forKey: "settled")
    _expectEqual(StorageRuntime.read("settled"), "final")
    _expectEqual(store.lock.withLock { store.values["settled"] }, "final")
    StorageRuntime.install(nil)
  }
  @Test
  func testOptionalSceneStorageReadsNilAfterAnotherWrapperRemovesTheKey() {
    var values: [String: String] = [:]
    StorageRuntime.install(StorageAdapter(read: { values[$0] }, write: { values[$0] = $1 }, remove: { values[$0] = nil }))
    let first = SceneStorage<String?>("draft")
    let second = SceneStorage<String?>("draft")
    first.wrappedValue = "hello"
    _expectEqual(first.wrappedValue, "hello")
    _expectEqual(second.wrappedValue, "hello")
    first.wrappedValue = nil
    _expectEqual(first.wrappedValue, nil)
    _expectEqual(second.wrappedValue, nil, "a removed key reads as nil, not as the value this wrapper cached")
  }

  @Test
  func testOptionalSceneStorageKeepsItsValueWhenNoStorageIsInstalled() {
    StorageRuntime.install(nil)
    let wrapper = SceneStorage<String?>("memory-only")
    wrapper.wrappedValue = "kept"
    _expectEqual(wrapper.wrappedValue, "kept", "with no adapter the in-memory value is the only copy")
  }

}
