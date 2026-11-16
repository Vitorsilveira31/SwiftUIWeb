@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// Storage primitives shared by SwiftUIWeb's native, WASI, and browser hosts.
///
/// The Core module intentionally knows nothing about JavaScript or a browser
/// API. Small SwiftUI-compatible values are represented as strings at this
/// boundary; a host decides where those strings live (UserDefaults,
/// localStorage, sessionStorage, or a process fallback).

@_spi(Renderer) import SwiftUIWebTransferable
package enum StorageScope: String, Hashable, Sendable {
  /// Values that survive browser tabs and application launches.
  case app
  /// Values that survive reloads in one browser tab/scene, but not a new tab.
  case scene
}

package enum StorageError: Error, Equatable, Sendable, CustomStringConvertible {
  case unavailable
  case quotaExceeded
  case transactionConflict(expected: UInt64, actual: UInt64)
  case revisionExhausted
  case invalidKey
  case host(String)

  package var description: String {
    switch self {
    case .unavailable: return "Storage is unavailable on this host"
    case .quotaExceeded: return "Storage quota was exceeded"
    case .transactionConflict(let expected, let actual):
      return "Storage transaction expected revision \(expected), found \(actual)"
    case .revisionExhausted: return "Storage revision counter is exhausted"
    case .invalidKey: return "Storage keys must not be empty"
    case .host(let message): return message
    }
  }
}

package enum StorageMutation: Sendable, Equatable {
  case set(key: String, value: String)
  case remove(key: String)
}

/// Neutral persistence boundary used by WASM/browser hosts. `write` is
/// allowed to be a cheap enqueue operation. Hosts that batch writes (the
/// browser adapter does this) provide `flush`; native adapters can omit it.
package struct StorageAdapter {
  package let read: (String) -> String?
  package let write: (String, String) -> Void
  /// Optional throwing write used by hosts whose storage API can reject a
  /// mutation (for example browser quota/security errors). The original
  /// non-throwing `write` remains source-compatible for simple adapters.
  package let throwingWrite: ((String, String) throws -> Void)?
  package let remove: ((String) -> Void)?
  package let flush: (() -> Void)?
  /// Optional host-native atomic commit. Returning the new revision lets the
  /// cache participate in optimistic transactions without a second roundtrip.
  package let transaction: (([StorageMutation], UInt64?) throws -> UInt64)?
  package let quotaBytes: Int?
  package let revision: (() -> UInt64)?

  package init(
    read: @escaping (String) -> String?,
    write: @escaping (String, String) -> Void,
    throwingWrite: ((String, String) throws -> Void)? = nil,
    remove: ((String) -> Void)? = nil,
    flush: (() -> Void)? = nil,
    transaction: (([StorageMutation], UInt64?) throws -> UInt64)? = nil,
    quotaBytes: Int? = nil,
    revision: (() -> UInt64)? = nil
  ) {
    self.read = read
    self.write = write
    self.throwingWrite = throwingWrite
    self.remove = remove
    self.flush = flush
    self.transaction = transaction
    self.quotaBytes = quotaBytes
    self.revision = revision
  }
}

private enum _ProcessStorage {
  private final class Values: @unchecked Sendable {
    let lock = _RuntimeLock()
    var app: [String: String] = .init()
    var scene: [String: String] = .init()
  }
  private static let values = Values()
  static var appValues: [String: String] {
    get { values.lock.withLock { values.app } }
    set { values.lock.withLock { values.app = newValue } }
  }
  static var sceneValues: [String: String] {
    get { values.lock.withLock { values.scene } }
    set { values.lock.withLock { values.scene = newValue } }
  }
}

/// Installs host storage and keeps the hot `@AppStorage`/`@SceneStorage`
/// access path in Swift memory. Reads call a host adapter only once per key
/// until invalidated. Writes update the cache immediately and are forwarded
/// to the adapter, whose `flush` can batch the actual browser calls.
package enum StorageRuntime {
  private final class State: @unchecked Sendable {
    var app: StorageAdapter? = {
    return StorageAdapter(
      read: { _ProcessStorage.appValues[$0] },
      write: { _ProcessStorage.appValues[$0] = $1 },
      remove: { _ProcessStorage.appValues[$0] = nil }
    )
    }()
    var scene: StorageAdapter? = {
    return StorageAdapter(
      read: { _ProcessStorage.sceneValues[$0] },
      write: { _ProcessStorage.sceneValues[$0] = $1 },
      remove: { _ProcessStorage.sceneValues[$0] = nil }
    )
    }()
    // One cache per scope, indexed by key: the two scopes are fixed, so they are two fields rather than tables keyed
    // by the scope (Embedded Swift emits the hashed-collection code once per key type).
    var appCache = ScopeCache()
    var sceneCache = ScopeCache()
    var sceneSharesAppAdapter = false
    var reloadGeneration: UInt64 = 0
    var lastError: StorageError?
    /// Writes the host refused so far; a wrapper compares it around its own write to keep the previous value.
    var failedWrites: UInt64 = 0
  }
  /// The values read or written for one scope, the keys known to be missing, and the scope's revision.
  private struct ScopeCache {
    var values: [String: String] = .init()
    var missing: Set<String> = []
    var revision: UInt64 = 0

    mutating func forget(_ key: String) {
      values[key] = nil
      missing.remove(key)
    }
  }
  private static let state = State()
  private static func cache(_ scope: StorageScope) -> ScopeCache {
    switch scope {
    case .app: return state.appCache
    case .scene: return state.sceneCache
    }
  }
  private static func withCache(_ scope: StorageScope, _ body: (inout ScopeCache) -> Void) {
    switch scope {
    case .app: body(&state.appCache)
    case .scene: body(&state.sceneCache)
    }
  }
  private static var app: StorageAdapter? {
    get { state.app }
    set { state.app = newValue }
  }
  private static var scene: StorageAdapter? {
    get { state.scene }
    set { state.scene = newValue }
  }
  private static var sceneSharesAppAdapter: Bool {
    get { state.sceneSharesAppAdapter }
    set { state.sceneSharesAppAdapter = newValue }
  }
  private static func setRevisions(app appRevision: UInt64, scene sceneRevision: UInt64) {
    state.appCache.revision = appRevision
    state.sceneCache.revision = sceneRevision
  }
  private static var _reloadGeneration: UInt64 {
    get { state.reloadGeneration }
    set { state.reloadGeneration = newValue }
  }
  private static var _lastError: StorageError? {
    get { state.lastError }
    set { state.lastError = newValue }
  }
  /// Every stored member above is read and written under this lock. The
  /// runtime is process-global; native hosts and the native test suite reach
  /// it from several threads at once (an install on one thread while a view
  /// on another reads its `@AppStorage`). In Embedded Swift the lock is a
  /// no-op. It is recursive, so the public entry points below can call each
  /// other and the private helpers assume the lock is already held.
  private static let lock = _RuntimeLock()

  package static var reloadGeneration: UInt64 { lock.withLock { _reloadGeneration } }
  /// The most recent non-throwing storage error (for example an AppStorage
  /// setter rejected by browser quota). Transactional callers still receive
  /// the typed error synchronously; this diagnostic covers SwiftUI-shaped
  /// property-wrapper setters, whose API cannot throw.
  package static var lastError: StorageError? { lock.withLock { _lastError } }

  /// Source-compatible access to the original app adapter property.
  package static var adapter: StorageAdapter? { lock.withLock { app } }
  /// The scene/session adapter. Browser hosts install sessionStorage here.
  package static var sceneAdapter: StorageAdapter? { lock.withLock { scene } }

  package static func install(_ adapter: StorageAdapter?) {
    lock.withLock {
      app = adapter
      scene = adapter
      sceneSharesAppAdapter = true
      setRevisions(app: app?.revision?() ?? 0, scene: scene?.revision?() ?? 0)
      _lastError = nil
      _invalidateCache()
    }
  }

  /// Installs independent app and scene stores. The overload is intentionally
  /// in Core so normal SwiftUI source never needs to choose a Web backend.
  package static func install(appAdapter: StorageAdapter?, sceneAdapter: StorageAdapter?) {
    lock.withLock {
      app = appAdapter
      scene = sceneAdapter
      sceneSharesAppAdapter = false
      setRevisions(app: app?.revision?() ?? 0, scene: scene?.revision?() ?? 0)
      _lastError = nil
      _invalidateCache()
    }
  }

  package static func install(_ adapter: StorageAdapter?, for scope: StorageScope) {
    lock.withLock {
      switch scope {
      case .app: install(appAdapter: adapter, sceneAdapter: scene)
      case .scene: install(appAdapter: app, sceneAdapter: adapter)
      }
    }
  }

  package static func hasAdapter(for scope: StorageScope) -> Bool {
    lock.withLock { adapter(for: scope) != nil }
  }

  /// Reads a value through the cache. A missing key is cached too, avoiding
  /// repeated JS `getItem` calls while a view is being rebuilt.
  package static func read(_ key: String, scope: StorageScope = .app) -> String? {
    lock.withLock { _read(key, scope: scope) }
  }

  private static func _read(_ key: String, scope: StorageScope) -> String? {
    guard !key.isEmpty else { _lastError = .invalidKey; return nil }
    guard let adapter = adapter(for: scope) else { return nil }
    let cached = cache(scope)
    if let value = cached.values[key] { return value }
    if cached.missing.contains(key) { return nil }
    guard let value = adapter.read(backendKey(key, scope: scope)) else {
      withCache(scope) { _ = $0.missing.insert(key) }
      return nil
    }
    withCache(scope) { $0.values[key] = value }
    return value
  }

  /// Caches the value now current for a scoped key, replacing any cached value or missing mark.
  private static func _setCached(_ value: String, scope: StorageScope, key: String) {
    withCache(scope) {
      $0.values[key] = value
      $0.missing.remove(key)
    }
  }

  /// Drops the cached value and missing mark of one scoped key.
  private static func _forget(scope: StorageScope, key: String) {
    withCache(scope) { $0.forget(key) }
  }

  /// Updates the in-memory value synchronously and lets the host decide when
  /// to perform its physical write. This preserves SwiftUI's immediate
  /// binding semantics without forcing a synchronous browser round trip.
  package static func write(_ value: String, forKey key: String, scope: StorageScope = .app) {
    lock.withLock {
      _write(value, forKey: key, scope: scope)
      if _lastError != nil { state.failedWrites &+= 1 }
    }
  }

  /// The number of writes the host has refused; see `AppStorage.wrappedValue`.
  package static var failedWrites: UInt64 { lock.withLock { state.failedWrites } }

  private static func _write(_ value: String, forKey key: String, scope: StorageScope) {
    guard let adapter = adapter(for: scope) else { _lastError = .unavailable; return }
    guard !key.isEmpty else { _lastError = .invalidKey; return }
    guard cache(scope).revision < UInt64.max else {
      _lastError = .revisionExhausted
      return
    }
    if let quota = adapter.quotaBytes {
      let (keyBytes, keyOverflow) = key.utf8.count.addingReportingOverflow(value.utf8.count)
      if keyOverflow || keyBytes > quota {
        _lastError = .quotaExceeded
        return
      }
    }
    let physicalKey = backendKey(key, scope: scope)
    do {
      if let throwingWrite = adapter.throwingWrite {
        try throwingWrite(physicalKey, value)
      } else {
        adapter.write(physicalKey, value)
      }
    } catch let error as StorageError {
      _lastError = error
      _invalidateCache(scope: scope, key: key)
      return
    } catch {
      // Embedded Swift intentionally does not ship the generic reflection
      // implementation behind String(describing:). Keep the public error
      // typed and stable instead of making the storage facade depend on it.
      _lastError = .host("Storage host operation failed")
      _invalidateCache(scope: scope, key: key)
      return
    }
    _setCached(value, scope: scope, key: key)
    withCache(scope) { $0.revision += 1 }
    _lastError = nil
  }

  package static func revision(for scope: StorageScope = .app) -> UInt64 {
    lock.withLock { cache(scope).revision }
  }

  /// Commits a batch of writes/removals as one logical storage transaction.
  /// Browser adapters can provide a true IndexedDB/localStorage atomic commit;
  /// the fallback performs all validation first and then updates its cache in
  /// one turn, preserving the same optimistic-concurrency contract. A host
  /// exposing a throwing writer should also expose `transaction` when physical
  /// rollback is required; without it, a failure after an earlier host write
  /// cannot be undone by this Foundation-free facade.
  @discardableResult
  package static func transaction(
    _ mutations: [StorageMutation],
    scope: StorageScope = .app,
    expectedRevision: UInt64? = nil
  ) throws -> UInt64 {
    try lock.withLock { try _transaction(mutations, scope: scope, expectedRevision: expectedRevision) }
  }

  private static func _transaction(
    _ mutations: [StorageMutation],
    scope: StorageScope,
    expectedRevision: UInt64?
  ) throws -> UInt64 {
    guard let adapter = adapter(for: scope) else {
      _lastError = .unavailable
      throw StorageError.unavailable
    }
    guard mutations.allSatisfy({ mutation in
      switch mutation {
      case .set(let key, _), .remove(let key): return !key.isEmpty
      }
    }) else { _lastError = .invalidKey; throw StorageError.invalidKey }
    let actual = cache(scope).revision
    if let expectedRevision, expectedRevision != actual {
      _lastError = .transactionConflict(expected: expectedRevision, actual: actual)
      throw StorageError.transactionConflict(expected: expectedRevision, actual: actual)
    }
    if let quota = adapter.quotaBytes {
      let bytes = mutations.reduce(into: 0) { total, mutation in
        switch mutation {
        case .set(let key, let value):
          let (keyBytes, keyOverflow) = total.addingReportingOverflow(key.utf8.count)
          let (valueBytes, valueOverflow) = keyBytes.addingReportingOverflow(value.utf8.count)
          total = keyOverflow || valueOverflow ? Int.max : valueBytes
        case .remove(let key):
          let (next, overflow) = total.addingReportingOverflow(key.utf8.count)
          total = overflow ? Int.max : next
        }
      }
      if bytes > quota {
        _lastError = .quotaExceeded
        throw StorageError.quotaExceeded
      }
    }
    let nextRevision: UInt64
    if let transaction = adapter.transaction {
      do {
        nextRevision = try transaction(mutations.map { mutation in
        switch mutation {
        case .set(let key, let value): return .set(key: backendKey(key, scope: scope), value: value)
        case .remove(let key): return .remove(key: backendKey(key, scope: scope))
        }
        }, expectedRevision)
      } catch let error as StorageError {
        _lastError = error
        throw error
      } catch {
        let wrapped = StorageError.host("Storage host operation failed")
        _lastError = wrapped
        throw wrapped
      }
    } else {
      // The ordinary `write` path is intentionally non-throwing. For a host
      // with no throwing writer this loop cannot fail; throwing writers are
      // supported for diagnostics, but physical atomicity belongs to the host
      // `transaction` closure.
      let delta = UInt64(mutations.isEmpty ? 1 : mutations.count)
      guard actual <= UInt64.max - delta else {
        _lastError = .revisionExhausted
        throw StorageError.revisionExhausted
      }
      do {
        for mutation in mutations {
          switch mutation {
          case .set(let key, let value):
            if let throwingWrite = adapter.throwingWrite {
              try throwingWrite(backendKey(key, scope: scope), value)
            } else {
              adapter.write(backendKey(key, scope: scope), value)
            }
          case .remove(let key):
            if let remove = adapter.remove { remove(backendKey(key, scope: scope)) }
            // Without a remove hook the value is left as it is; writing "" would read back as a value, not as removed.
            else { adapter.remove?(backendKey(key, scope: scope)) }
          }
        }
      } catch let error as StorageError {
        _lastError = error
        throw error
      } catch {
        let wrapped = StorageError.host("Storage host operation failed")
        _lastError = wrapped
        throw wrapped
      }
      nextRevision = actual + delta
    }
    guard nextRevision >= actual else {
      let error = StorageError.host("Storage adapter returned a backwards revision")
      _lastError = error
      throw error
    }
    for mutation in mutations {
      switch mutation {
      case .set(let key, let value):
        _setCached(value, scope: scope, key: key)
      case .remove(let key):
        _forget(scope: scope, key: key)
        withCache(scope) { _ = $0.missing.insert(key) }
      }
    }
    withCache(scope) { $0.revision = nextRevision }
    _lastError = nil
    return nextRevision
  }

  /// Drops all cached values and asks the next read to reload from the host.
  /// This is used after a browser reload/session handoff and is deliberately
  /// separate from `install`, so a live Fiber tree keeps its state identity.
  package static func reload() {
    lock.withLock {
      _invalidateCache()
      _reloadGeneration &+= 1
    }
  }

  /// Flushes pending host writes. BrowserSession calls this after a render;
  /// applications may call it explicitly before handing off/terminating.
  package static func flush() {
    let (app, scene) = lock.withLock { (self.app, sceneSharesAppAdapter ? nil : self.scene) }
    app?.flush?()
    scene?.flush?()
  }

  /// Invalidates one key (normally from a browser `storage` event), or the
  /// complete cache when a host is replaced/reloaded.
  package static func invalidateCache(scope: StorageScope? = nil, key: String? = nil) {
    lock.withLock { _invalidateCache(scope: scope, key: key) }
  }

  private static func _invalidateCache(scope: StorageScope? = nil, key: String? = nil) {
    guard scope != nil || key != nil else {
      for candidateScope in [StorageScope.app, .scene] {
        withCache(candidateScope) {
          $0.values.removeAll(keepingCapacity: true)
          $0.missing.removeAll(keepingCapacity: true)
        }
      }
      refreshRevision(for: .app)
      refreshRevision(for: .scene)
      return
    }
    // With a key, only that key's entries are visited; a scope-only invalidation drops the scope's whole cache.
    for candidateScope in [StorageScope.app, .scene] where scope == nil || candidateScope == scope {
      withCache(candidateScope) { cached in
        if let key {
          cached.forget(key)
        } else {
          cached.values.removeAll(keepingCapacity: true)
          cached.missing.removeAll(keepingCapacity: true)
        }
      }
    }
    if let scope {
      refreshRevision(for: scope)
    } else {
      refreshRevision(for: .app)
      refreshRevision(for: .scene)
    }
  }

  private static func refreshRevision(for scope: StorageScope) {
    if let value = adapter(for: scope)?.revision?() { withCache(scope) { $0.revision = value } }
  }

  private static func adapter(for scope: StorageScope) -> StorageAdapter? {
    switch scope {
    case .app: return app
    case .scene: return scene
    }
  }

  private static func backendKey(_ key: String, scope: StorageScope) -> String {
    // A single adapter is retained for source compatibility with the old API.
    // Prefixing its scene keys prevents a scene value from overwriting an app
    // value when both are backed by one dictionary/UserDefaults suite.
    if scope == .scene && sceneSharesAppAdapter {
      return "__SwiftUIWeb.SceneStorage.\(key)"
    }
    return key
  }
}

func _encodeStorageValue<Value>(_ value: Value) -> String? {
  if let value = value as? TabViewCustomization { return value._storageValue }
  if let value = value as? String { return value }
  if let value = value as? Bool { return value ? "true" : "false" }
  if let value = value as? Int { return String(value) }
  if let value = value as? Int8 { return String(value) }
  if let value = value as? Int16 { return String(value) }
  if let value = value as? Int32 { return String(value) }
  if let value = value as? Int64 { return String(value) }
  if let value = value as? UInt { return String(value) }
  if let value = value as? UInt8 { return String(value) }
  if let value = value as? UInt16 { return String(value) }
  if let value = value as? UInt32 { return String(value) }
  if let value = value as? UInt64 { return String(value) }
  if let value = value as? Float { return String(value) }
  if let value = value as? Double { return String(value) }
  if let value = value as? URL { return value.absoluteString }
  if let value = value as? Data { return value.base64EncodedString() }
  return nil
}

func _decodeStorageValue<Value>(_ raw: String, as type: Value.Type) -> Value? {
  if type == TabViewCustomization.self { return TabViewCustomization(_storageValue: raw) as? Value }
  if type == String.self { return raw as? Value }
  if type == Bool.self {
    switch raw.lowercased() {
    case "true", "1", "yes": return true as? Value
    case "false", "0", "no": return false as? Value
    default: return nil
    }
  }
  if type == Int.self { return Int(raw) as? Value }
  if type == Int8.self { return Int8(raw) as? Value }
  if type == Int16.self { return Int16(raw) as? Value }
  if type == Int32.self { return Int32(raw) as? Value }
  if type == Int64.self { return Int64(raw) as? Value }
  if type == UInt.self { return UInt(raw) as? Value }
  if type == UInt8.self { return UInt8(raw) as? Value }
  if type == UInt16.self { return UInt16(raw) as? Value }
  if type == UInt32.self { return UInt32(raw) as? Value }
  if type == UInt64.self { return UInt64(raw) as? Value }
  if type == Float.self { return Float(raw) as? Value }
  if type == Double.self { return Double(raw) as? Value }
  if type == URL.self { return URL(string: raw) as? Value }
  if type == Data.self { return Data(base64Encoded: raw) as? Value }
  return nil
}

/// Embedded/WASI fallback. Persistence is supplied by a host adapter when
/// available; otherwise StorageRuntime's process adapter is deterministic and
/// survives wrapper/view-value copies for the lifetime of the process.
private final class InMemoryStorage<Value> {
  var value: Value
  init(_ value: Value) { self.value = value }
}

/// One observation source per stored key. A view that reads an `@AppStorage` (or `@SceneStorage`) depends on its key,
/// and a write through any wrapper with that key renders those views again, as SwiftUI's wrappers do: there, writing
/// `$darkMode` from a child view updates the parent that declared `@AppStorage("darkMode")`. Keys of different suites
/// share a source, which only renders a view more than it needs.
enum _StorageObservation {
#if hasFeature(Embedded)
  @MainActor private static var sources: [String: Published<UInt32>] = .init()

  @MainActor private static func source(_ key: String) -> Published<UInt32> {
    if let source = sources[key] { return source }
    let source = Published<UInt32>(wrappedValue: 0)
    sources[key] = source
    return source
  }

  // The wrappers are not main-actor isolated, as SwiftUI's are not; the page reads and writes them on its one thread.
  static func read(_ key: String) { _assumeMainActor { _ = source(key).wrappedValue } }
  // `&+=` goes through Published's `_modify`, which does not make the writing view an observer of its own write.
  static func changed(_ key: String) { _assumeMainActor { source(key).wrappedValue &+= 1 } }
#else
  static func read(_ key: String) {}
  static func changed(_ key: String) {}
#endif
}

/// Reads and writes through `UserDefaults` (`store`, or `.standard`), which keeps the app scope in
/// `localStorage`, as SwiftUI's `AppStorage` does through Foundation's defaults.
@propertyWrapper public struct AppStorage<Value>: DynamicProperty {
  private let storage: InMemoryStorage<Value>
  // The conversions are closures chosen when the wrapper is created, so the generic getter and setter never
  // reference the cast-based `_decodeStorageValue`: Embedded Swift cannot specialize those casts for `Optional`.
  private let read: () -> Value?
  private let write: (Value) -> Void
  /// The key whose observation source this wrapper reads and invalidates (`nil`: none).
  private let observedKey: String?
  @_disfavoredOverload
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    storage = InMemoryStorage(wrappedValue)
    observedKey = "app." + key
    read = { store._rawValue(forKey: key).flatMap { _decodeStorageValue($0, as: Value.self) } }
    write = { value in
      if let encoded = _encodeStorageValue(value) { store._setRawValue(encoded, forKey: key) }
    }
  }
  @_spi(Renderer) public init(initial: Value, key: String? = nil, read: @escaping () -> Value?, write: @escaping (Value) -> Void) {
    storage = InMemoryStorage(initial)
    observedKey = key.map { "app." + $0 }
    self.read = read
    self.write = write
  }
  public var wrappedValue: Value {
    get {
      if let observedKey { _StorageObservation.read(observedKey) }
      if let value = read() { storage.value = value }
      return storage.value
    }
    nonmutating set {
      // A write the host refuses (quota, an unavailable store) leaves the stored value as it was, as Foundation's
      // defaults do: the wrapper keeps showing the last value that persisted.
      let refusedBefore = StorageRuntime.failedWrites
      let previous = storage.value
      storage.value = newValue
      write(newValue)
      if StorageRuntime.failedWrites != refusedBefore { storage.value = previous }
      if let observedKey { _StorageObservation.changed(observedKey) }
    }
  }
  public var projectedValue: Binding<Value> {
    // SAFETY: copies of a wrapper share its storage box, so the binding reads and writes the same value. Like SwiftUI's
    // wrappers they are used from views, on the main actor (the page's one thread in the browser).
    nonisolated(unsafe) let wrapper = self
    return Binding(get: { wrapper.wrappedValue }, set: { wrapper.wrappedValue = $0 })
  }
}

/// Scalar values stored as text. The conforming initializers below are chosen at compile time, so storing a `UInt`,
/// an `Int8` or an enum never reaches the cast-based codec, which Embedded Swift cannot specialize for them.
public protocol _AppStorageScalar {
  // Underscored, like the protocol: they are the storage codec's, not API of `Int` or `String`.
  static func _fromStorageString(_ text: String) -> Self?
  var _storageString: String { get }
}
extension String: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> String? { text }
  public var _storageString: String { self }
}
extension Bool: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Bool? {
    switch text.lowercased() { case "true", "1", "yes": return true; case "false", "0", "no": return false; default: return nil }
  }
  public var _storageString: String { self ? "true" : "false" }
}
extension Int: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}
extension Int8: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}
extension Int16: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}
extension Int32: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}
extension Int64: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}
extension UInt: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}
extension UInt8: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}
extension UInt16: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}
extension UInt32: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}
extension UInt64: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}
extension Float: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}
extension Double: _AppStorageScalar {
  public static func _fromStorageString(_ text: String) -> Self? { Self(text) }
  public var _storageString: String { String(self) }
}

extension AppStorage where Value: _AppStorageScalar {
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    self.init(initial: wrappedValue, key: key, read: { store._rawValue(forKey: key).flatMap { Value._fromStorageString($0) } }, write: { value in
      store._setRawValue(value._storageString, forKey: key)
    })
  }
}

/// `@AppStorage("key") var mode: Mode = .a` for a String-backed enum.
extension AppStorage where Value: RawRepresentable, Value.RawValue == String {
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    self.init(initial: wrappedValue, key: key, read: { store._rawValue(forKey: key).flatMap { Value(rawValue: $0) } }, write: { value in
      store._setRawValue(value.rawValue, forKey: key)
    })
  }
}

/// `@AppStorage("key") var mode: Mode = .a` for an Int-backed enum.
extension AppStorage where Value: RawRepresentable, Value.RawValue == Int {
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    self.init(initial: wrappedValue, key: key, read: { store._rawValue(forKey: key).flatMap { Int($0) }.flatMap { Value(rawValue: $0) } }, write: { value in
      store._setRawValue(String(value.rawValue), forKey: key)
    })
  }
}

/// `@AppStorage("key") var link = URL(...)`: the URL's text is kept, as `UserDefaults` keeps a URL.
extension AppStorage where Value == URL {
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    self.init(initial: wrappedValue, key: key, read: { store._rawValue(forKey: key).flatMap { URL(string: $0) } }, write: { value in
      store._setRawValue(value.absoluteString, forKey: key)
    })
  }
}

/// `@AppStorage("key") var blob = Data()`: the bytes are kept as base64 text.
extension AppStorage where Value == Data {
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    self.init(initial: wrappedValue, key: key, read: { store._rawValue(forKey: key).flatMap { Data(base64Encoded: $0) } }, write: { value in
      store._setRawValue(value.base64EncodedString(), forKey: key)
    })
  }
}

/// `@AppStorage("key") var mode: Mode?` for an enum with a String or Int raw value: unset reads as `nil`.
extension AppStorage {
  public init<R: RawRepresentable>(_ key: String, store: UserDefaults? = nil) where Value == R?, R.RawValue == String {
    let store = store ?? .standard
    self.init(initial: nil, key: key, read: { store._rawValue(forKey: key).flatMap { R(rawValue: $0) }.map { Optional($0) } }, write: { value in
      if let value { store._setRawValue(value.rawValue, forKey: key) } else { store.removeObject(forKey: key) }
    })
  }

  public init<R: RawRepresentable>(_ key: String, store: UserDefaults? = nil) where Value == R?, R.RawValue == Int {
    let store = store ?? .standard
    self.init(initial: nil, key: key, read: { store._rawValue(forKey: key).flatMap { Int($0) }.flatMap { R(rawValue: $0) }.map { Optional($0) } }, write: { value in
      if let value { store._setRawValue(String(value.rawValue), forKey: key) } else { store.removeObject(forKey: key) }
    })
  }
}

/// `@AppStorage("key") var link: URL?` and `Data?`: unset reads as `nil`, assigning `nil` removes the key.
extension AppStorage where Value == URL? {
  public init(_ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    self.init(initial: nil, key: key, read: { store._rawValue(forKey: key).flatMap { URL(string: $0) }.map { Optional($0) } }, write: { value in
      if let value { store._setRawValue(value.absoluteString, forKey: key) } else { store.removeObject(forKey: key) }
    })
  }
}

extension AppStorage where Value == Data? {
  public init(_ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    self.init(initial: nil, key: key, read: { store._rawValue(forKey: key).flatMap { Data(base64Encoded: $0) }.map { Optional($0) } }, write: { value in
      if let value { store._setRawValue(value.base64EncodedString(), forKey: key) } else { store.removeObject(forKey: key) }
    })
  }
}

/// `@AppStorage("key") var value: String?` and friends: unset reads as `nil`, assigning `nil` removes the key.
extension AppStorage where Value == String? {
  public init(_ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    self.init(initial: nil, key: key, read: { store._rawValue(forKey: key).map { Optional($0) } }, write: { value in
      if let value { store._setRawValue(value, forKey: key) } else { store.removeObject(forKey: key) }
    })
  }
}

extension AppStorage where Value == Int? {
  public init(_ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    self.init(initial: nil, key: key, read: { store._rawValue(forKey: key).flatMap { Int($0) }.map { Optional($0) } }, write: { value in
      if let value { store._setRawValue(String(value), forKey: key) } else { store.removeObject(forKey: key) }
    })
  }
}

extension AppStorage where Value == Double? {
  public init(_ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    self.init(initial: nil, key: key, read: { store._rawValue(forKey: key).flatMap { Double($0) }.map { Optional($0) } }, write: { value in
      if let value { store._setRawValue(String(value), forKey: key) } else { store.removeObject(forKey: key) }
    })
  }
}

extension AppStorage where Value == Bool? {
  public init(_ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    // The same parsing as the non-optional Bool: "yes" and "1" are true, and an unparseable value reads as unset.
    self.init(initial: nil, key: key, read: { store._rawValue(forKey: key).flatMap { Bool._fromStorageString($0) }.map { Optional($0) } }, write: { value in
      if let value { store._setRawValue(value ? "true" : "false", forKey: key) } else { store.removeObject(forKey: key) }
    })
  }
}

/// Values kept for the scene (the page session, `sessionStorage`), as SwiftUI's `SceneStorage` keeps them for a scene.
@propertyWrapper public struct SceneStorage<Value>: DynamicProperty {
  private let storage: InMemoryStorage<Value>
  private let key: String
  // Chosen when the wrapper is created, as AppStorage's are: `nil` from `write` removes the key.
  private let read: (String) -> Value?
  private let write: (Value) -> String?
  /// What an unset key reads as, for the optional wrappers (`nil`): another wrapper of the same key may have removed
  /// it, and this one must not keep returning the value it cached before. `nil` here: keep the cached value.
  private let unset: Value?
  init(initial: Value, key: String, unset: Value? = nil, read: @escaping (String) -> Value?, write: @escaping (Value) -> String?) {
    storage = InMemoryStorage(initial)
    self.key = key
    self.unset = unset
    self.read = read
    self.write = write
  }
  public var wrappedValue: Value {
    get {
      _StorageObservation.read("scene." + key)
      if let raw = StorageRuntime.read(key, scope: .scene) {
        if let value = read(raw) { storage.value = value }
      } else if let unset, StorageRuntime.hasAdapter(for: .scene) {
        // Another wrapper removed the key. Without an adapter nothing is stored at all, and the in-memory value is the
        // only copy, so it stays.
        storage.value = unset
      }
      return storage.value
    }
    nonmutating set {
      storage.value = newValue
      if let encoded = write(newValue) {
        StorageRuntime.write(encoded, forKey: key, scope: .scene)
      } else {
        _ = try? StorageRuntime.transaction([.remove(key: key)], scope: .scene)
      }
      _StorageObservation.changed("scene." + key)
    }
  }
  public var projectedValue: Binding<Value> {
    // SAFETY: copies of a wrapper share its storage box, so the binding reads and writes the same value. Like SwiftUI's
    // wrappers they are used from views, on the main actor (the page's one thread in the browser).
    nonisolated(unsafe) let wrapper = self
    return Binding(get: { wrapper.wrappedValue }, set: { wrapper.wrappedValue = $0 })
  }
}

// SwiftUI's overloads: the value types a scene can store, each with its text form.
extension SceneStorage {
  public init(wrappedValue: Value, _ key: String) where Value == Bool {
    self.init(initial: wrappedValue, key: key, read: { Bool._fromStorageString($0) }, write: { $0 ? "true" : "false" })
  }
  public init(wrappedValue: Value, _ key: String) where Value == Int {
    self.init(initial: wrappedValue, key: key, read: { Int($0) }, write: { String($0) })
  }
  public init(wrappedValue: Value, _ key: String) where Value == Double {
    self.init(initial: wrappedValue, key: key, read: { Double($0) }, write: { String($0) })
  }
  public init(wrappedValue: Value, _ key: String) where Value == String {
    self.init(initial: wrappedValue, key: key, read: { $0 }, write: { $0 })
  }
  public init(wrappedValue: Value, _ key: String) where Value == URL {
    self.init(initial: wrappedValue, key: key, read: { URL(string: $0) }, write: { $0.absoluteString })
  }
  public init(wrappedValue: Value, _ key: String) where Value == Date {
    self.init(initial: wrappedValue, key: key, read: { Double($0).map { Date(timeIntervalSinceReferenceDate: $0) } },
              write: { String($0.timeIntervalSinceReferenceDate) })
  }
  public init(wrappedValue: Value, _ key: String) where Value == Data {
    self.init(initial: wrappedValue, key: key, read: { Data(base64Encoded: $0) }, write: { $0.base64EncodedString() })
  }
  public init(wrappedValue: Value, _ key: String) where Value: RawRepresentable, Value.RawValue == Int {
    self.init(initial: wrappedValue, key: key, read: { Int($0).flatMap { Value(rawValue: $0) } }, write: { String($0.rawValue) })
  }
  public init(wrappedValue: Value, _ key: String) where Value: RawRepresentable, Value.RawValue == String {
    self.init(initial: wrappedValue, key: key, read: { Value(rawValue: $0) }, write: { $0.rawValue })
  }
}

/// A `TabView`'s customization, empty until the person changes it, as in SwiftUI. The scene keeps it for the page session;
/// `store` is accepted as SwiftUI accepts it.
extension SceneStorage {
  public init(wrappedValue: Value = TabViewCustomization(), _ key: String, store: UserDefaults? = nil) where Value == TabViewCustomization {
    self.init(initial: wrappedValue, key: key, read: { TabViewCustomization(_storageValue: $0) }, write: { $0._storageValue })
  }
}

extension AppStorage {
  public init(wrappedValue: Value = TabViewCustomization(), _ key: String, store: UserDefaults? = nil) where Value == TabViewCustomization {
    let store = store ?? .standard
    self.init(initial: wrappedValue, key: key, read: { store._rawValue(forKey: key).map { TabViewCustomization(_storageValue: $0) } }, write: { value in
      store._setRawValue(value._storageValue, forKey: key)
    })
  }
}

/// `@SceneStorage("key") var value: String?` and friends: unset reads as `nil`, assigning `nil` removes the key.
extension SceneStorage where Value: ExpressibleByNilLiteral {
  public init(_ key: String) where Value == Bool? {
    self.init(initial: nil, key: key, unset: .some(nil), read: { raw in Bool._fromStorageString(raw).map { Optional($0) } }, write: { $0.map { $0 ? "true" : "false" } })
  }
  public init(_ key: String) where Value == Int? {
    self.init(initial: nil, key: key, unset: .some(nil), read: { raw in Int(raw).map { Optional($0) } }, write: { $0.map { String($0) } })
  }
  public init(_ key: String) where Value == Double? {
    self.init(initial: nil, key: key, unset: .some(nil), read: { raw in Double(raw).map { Optional($0) } }, write: { $0.map { String($0) } })
  }
  public init(_ key: String) where Value == String? {
    self.init(initial: nil, key: key, unset: .some(nil), read: { Optional($0) }, write: { $0 })
  }
  public init(_ key: String) where Value == URL? {
    self.init(initial: nil, key: key, unset: .some(nil), read: { raw in URL(string: raw).map { Optional($0) } }, write: { $0?.absoluteString })
  }
  public init(_ key: String) where Value == Date? {
    self.init(initial: nil, key: key, unset: .some(nil), read: { raw in Double(raw).map { Optional(Date(timeIntervalSinceReferenceDate: $0)) } },
              write: { $0.map { String($0.timeIntervalSinceReferenceDate) } })
  }
  public init(_ key: String) where Value == Data? {
    self.init(initial: nil, key: key, unset: .some(nil), read: { raw in Data(base64Encoded: raw).map { Optional($0) } }, write: { $0?.base64EncodedString() })
  }
  public init<R>(_ key: String) where Value == R?, R: RawRepresentable, R.RawValue == String {
    self.init(initial: nil, key: key, unset: .some(nil), read: { raw in R(rawValue: raw).map { Optional($0) } }, write: { $0?.rawValue })
  }
  public init<R>(_ key: String) where Value == R?, R: RawRepresentable, R.RawValue == Int {
    self.init(initial: nil, key: key, unset: .some(nil), read: { raw in Int(raw).flatMap { R(rawValue: $0) }.map { Optional($0) } }, write: { $0.map { String($0.rawValue) } })
  }
}

// As in SwiftUI: a wrapper of a Sendable value may cross isolation domains; its storage box is shared, as SwiftUI's is.
extension AppStorage: @unchecked Sendable where Value: Sendable {}
extension SceneStorage: @unchecked Sendable where Value: Sendable {}
