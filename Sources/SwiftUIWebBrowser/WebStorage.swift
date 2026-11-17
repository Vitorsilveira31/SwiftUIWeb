/// Optional structured Web persistence.
///
/// Keep scalar preferences in `@AppStorage` and scene/session values in
/// `@SceneStorage`. This type is for larger Codable values that should not be
/// squeezed through Web Storage's string quota. The WebAssembly implementation
/// uses IndexedDB; native builds include a deterministic in-process fallback
/// so migration and reload behavior can be tested without a browser.

import SwiftUIWeb

#if !hasFeature(Embedded)
@MainActor private enum _WebIndexedDBFallbackStorage {
  static var values: [String: String] = .init()
  /// Bytes held per store (keyed by the store's name prefix). Computed on the first quota check, then kept by `write`.
  static var byteTotals: [String: Int] = .init()

  /// Stores `value` (nil removes it) and keeps the store's running total.
  static func write(_ key: String, _ value: String?, prefix: String) {
    let previous = values[key]?.utf8.count ?? 0
    values[key] = value
    if let total = byteTotals[prefix] { byteTotals[prefix] = total - previous + (value?.utf8.count ?? 0) }
  }
}
#endif

#if arch(wasm32) && hasFeature(Embedded)
import SwiftUIWebBrowserIO
#endif

public enum WebIndexedDBError: Error, Equatable, Sendable, CustomStringConvertible {
  case unavailable
  case cancelled
  case invalidKey
  case quotaExceeded
  case incompatibleVersion(found: Int, expected: Int)
  case migrationRequired(from: Int, to: Int)
  case encoding(String)
  case database(String)

  public var description: String {
    switch self {
    case .unavailable: return "IndexedDB is unavailable on this host"
    case .cancelled: return "IndexedDB operation was cancelled"
    case .invalidKey: return "IndexedDB keys must be non-empty and at most 1024 bytes"
    case .quotaExceeded: return "IndexedDB storage quota was exceeded"
    case .incompatibleVersion(let found, let expected):
      return "IndexedDB record version \(found) is newer than supported version \(expected)"
    case .migrationRequired(let from, let to):
      return "No IndexedDB migration is registered from version \(from) to \(to)"
    case .encoding(let message): return "IndexedDB encoding failed: \(message)"
    case .database(let message): return "IndexedDB error: \(message)"
    }
  }
}

private func _validateWebIndexedDBKey(_ key: String) throws {
  guard !key.isEmpty, key.utf8.count <= 1024 else {
    throw WebIndexedDBError.invalidKey
  }
}

/// Names come from the application and may come from data, so an empty name is refused as an error, not a trap.
private func _validateWebIndexedDBNames(_ databaseName: String, _ objectStoreName: String) throws {
  guard !databaseName.isEmpty, !objectStoreName.isEmpty else {
    throw WebIndexedDBError.database("IndexedDB database and object store names must not be empty")
  }
}

/// A name framed by its UTF-8 length, so names containing the separator cannot alias another (name, store, key).
private func _framedWebIndexedDBName(_ value: String) -> String {
  String(value.utf8.count) + ":" + value
}

/// The browser database that holds a store. Names without a "." keep the name earlier releases used
/// (`drafts.records`), so stored data stays where it is; only a pair where a name has a "." could alias another pair
/// (`("a.b", "c")` and `("a", "b.c")`), and it is framed instead. A framed name holds no "." at all (each name's dots and
/// percent signs are escaped, then length-framed), while every name an earlier release used holds one: a framed name is
/// never another store's legacy name, so migrating or cleaning up one store never touches another.
func _webIndexedDBPhysicalName(_ databaseName: String, _ objectStoreName: String) -> String {
  guard databaseName.contains(".") || objectStoreName.contains(".") else { return databaseName + "." + objectStoreName }
  func escaped(_ name: String) -> String {
    var result = ""
    for scalar in name.unicodeScalars {
      switch scalar {
      case "%": result += "%25"
      case ".": result += "%2E"
      default: result.unicodeScalars.append(scalar)
      }
    }
    return _framedWebIndexedDBName(result)
  }
  return "~" + escaped(databaseName) + escaped(objectStoreName)
}

/// The name earlier releases used for a pair whose names hold a ".", when it differs from today's: records found only
/// there are moved over on first read (see `load(key:)`).
func _webIndexedDBLegacyName(_ databaseName: String, _ objectStoreName: String) -> String? {
  let legacy = databaseName + "." + objectStoreName
  return legacy == _webIndexedDBPhysicalName(databaseName, objectStoreName) ? nil : legacy
}

#if hasFeature(Embedded)
/// A synchronous value migration. The public shape is preserved in Embedded
/// Swift, while serialization is delegated to the foreign/browser backend.
public struct WebIndexedDBMigration<Value> {
  public let fromVersion: Int
  public let toVersion: Int
  private let transform: (Value) throws -> Value

  public init(
    fromVersion: Int,
    toVersion: Int,
    transform: @escaping (Value) throws -> Value
  ) {
    precondition(toVersion > fromVersion, "IndexedDB migrations must advance the version")
    self.fromVersion = fromVersion
    self.toVersion = toVersion
    self.transform = transform
  }

  fileprivate func apply(_ value: Value) throws -> Value { try transform(value) }
}

/// Embedded façade for the IndexedDB store. `Codable` itself is unavailable
/// in Embedded Swift, so the generic surface intentionally carries no runtime
/// protocol constraint. This keeps call-site spelling stable without pulling
/// the unavailable Swift Codable runtime into the Wasm module.
private struct _EmbeddedIndexedEnvelope<Value: EmbeddedCodable>: EmbeddedCodable {
  let version: Int
  let value: Value
  func _embeddedJSONValue() throws -> _EmbeddedJSONValue { .object(["version": try version._embeddedJSONValue(), "value": try value._embeddedJSONValue()]) }
  static func _embeddedDecodeJSONValue(_ json: _EmbeddedJSONValue) throws -> Self {
    guard case .object(let object)=json, let v=object["version"], let value=object["value"] else { throw _EmbeddedCodableError.typeMismatch }
    return Self(version: try Int._embeddedDecodeJSONValue(v), value: try Value._embeddedDecodeJSONValue(value))
  }
}

@MainActor public final class WebIndexedDBStore<Value: EmbeddedCodable> {
  public let databaseName: String
  public let objectStoreName: String
  public let version: Int
  public let quotaBytes: Int?
  private let migrations: [WebIndexedDBMigration<Value>]
  public init(databaseName: String, objectStoreName: String = "records", version: Int = 1, quotaBytes: Int? = nil, migrations: [WebIndexedDBMigration<Value>] = []) {
    precondition(version >= 1 && version <= 2_147_483_647)
    precondition(quotaBytes == nil || quotaBytes! > 0)
    self.databaseName=databaseName; self.objectStoreName=objectStoreName; self.version=version; self.quotaBytes=quotaBytes; self.migrations=migrations.sorted{$0.fromVersion<$1.fromVersion}
  }
  private var db: BrowserIndexedDB { BrowserIndexedDB(databaseName: _webIndexedDBPhysicalName(databaseName, objectStoreName), version: version) }
  private func map(_ error: BrowserIOError) -> WebIndexedDBError {
    if error.code == -3 { return .quotaExceeded }
    if error.code == -7 { return .unavailable }
    if error.code == -4 { return .cancelled }
    return .database(error.message)
  }
  public func load(key: String) async throws -> Value? {
    try _validateWebIndexedDBNames(databaseName, objectStoreName)
    try _validateWebIndexedDBKey(key)
    var raw: [UInt8]?
    do { raw = try await db.get(key) }
    catch let error as BrowserIOError { throw map(error) }
    if raw == nil, let legacyName = _webIndexedDBLegacyName(databaseName, objectStoreName) {
      // A record an earlier release wrote under the old name is moved here, and removed there, so a later delete does
      // not bring it back.
      let legacy = BrowserIndexedDB(databaseName: legacyName, version: version)
      do {
        if let old = try await legacy.get(key) {
          try await db.put(old, forKey: key)
          try await legacy.remove(key)
          raw = old
        }
      } catch let error as BrowserIOError { throw map(error) }
    }
    guard let raw else { return nil }
    let envelope: _EmbeddedIndexedEnvelope<Value>
    do { envelope = try _EmbeddedJSONCodec.decode(_EmbeddedIndexedEnvelope<Value>.self, from: Data(raw)) }
    catch { throw WebIndexedDBError.encoding("Storage encoding failed") }
    guard envelope.version <= version else { throw WebIndexedDBError.incompatibleVersion(found: envelope.version, expected: version) }
    var current=envelope.value; var currentVersion=envelope.version
    while currentVersion < version {
      guard let migration=migrations.first(where:{$0.fromVersion==currentVersion}) else { throw WebIndexedDBError.migrationRequired(from: currentVersion, to: version) }
      current=try migration.apply(current); currentVersion=migration.toVersion
    }
    if envelope.version != version { try await save(current,key:key) }
    return current
  }
  public func save(_ value: Value, key: String) async throws {
    try _validateWebIndexedDBNames(databaseName, objectStoreName)
    try _validateWebIndexedDBKey(key)
    let bytes: [UInt8]
    do { bytes = Array(try _EmbeddedJSONCodec.encode(_EmbeddedIndexedEnvelope(version:version,value:value))) }
    catch { throw WebIndexedDBError.encoding("Storage encoding failed") }
    try await ensureQuota(replacing: [key: bytes])
    do { try await db.put(bytes, forKey: key) }
    catch let error as BrowserIOError { throw map(error) }
    try await forgetLegacy([key])
  }
  public func value(forKey key:String) async throws -> Value? { try await load(key:key) }
  public func setValue(_ value:Value, forKey key:String) async throws { try await save(value,key:key) }
  public func delete(key:String) async throws {
    try _validateWebIndexedDBNames(databaseName, objectStoreName)
    try _validateWebIndexedDBKey(key)
    // A deletion only frees space: it is never refused by the quota, even when the store is above it.
    do { try await db.remove(key) }
    catch let error as BrowserIOError { throw map(error) }
    try await forgetLegacy([key])
  }
  public func transaction(_ mutations: [(key: String, value: Value?)]) async throws {
    try _validateWebIndexedDBNames(databaseName, objectStoreName)
    for mutation in mutations { try _validateWebIndexedDBKey(mutation.key) }
    var writes: [BrowserIndexedDB.Mutation] = []
    for mutation in mutations {
      if let value = mutation.value {
        let bytes: [UInt8]
        do { bytes = Array(try _EmbeddedJSONCodec.encode(_EmbeddedIndexedEnvelope(version: version, value: value))) }
        catch { throw WebIndexedDBError.encoding("Storage encoding failed") }
        writes.append(.put(key: mutation.key, value: bytes))
      } else {
        writes.append(.remove(key: mutation.key))
      }
    }
    var replacements: [String: [UInt8]?] = .init()
    for (mutation, write) in zip(mutations, writes) {
      switch write {
      case .put(_, let bytes): replacements[mutation.key] = bytes
      case .remove: replacements[mutation.key] = nil
      case .removeAll: break
      }
    }
    try await ensureQuota(replacing: replacements)
    do { try await db.transaction(writes) }
    catch let error as BrowserIOError { throw map(error) }
    try await forgetLegacy(mutations.map(\.key))
  }

  /// Removes `keys` from the database an earlier release used for this store (see `_webIndexedDBLegacyName`): a key
  /// written or removed here must not come back from there on a later first read. Best effort: the operation it follows
  /// has already succeeded, and its caller must not see a failure for it.
  private func forgetLegacy(_ keys: [String]) async throws {
    guard let legacyName = _webIndexedDBLegacyName(databaseName, objectStoreName), !keys.isEmpty else { return }
    let legacy = BrowserIndexedDB(databaseName: legacyName, version: version)
    try? await legacy.transaction(keys.map { .remove(key: $0) })
  }

  /// Refuses `replacements` that would grow the store past its quota. The total is read from the database at each check,
  /// so writes by another instance or another tab count; a change that does not grow the store (a smaller value, a
  /// removal) is allowed even when the store is already above a quota lowered since.
  private func ensureQuota(replacing replacements: [String: [UInt8]?]) async throws {
    guard let quotaBytes else { return }
    do {
      var total = 0
      var delta = 0
      for key in try await db.keys() {
        guard let value = try await db.get(key) else { continue }
        if let replacement = replacements[key] {
          delta += (replacement?.count ?? 0) - value.count
          total += replacement?.count ?? 0
        } else {
          total += value.count
        }
      }
      for (key, replacement) in replacements {
        // A key the store does not hold yet adds its whole size.
        if try await db.get(key) != nil { continue }
        delta += replacement?.count ?? 0
        total += replacement?.count ?? 0
      }
      if delta > 0, total > quotaBytes { throw WebIndexedDBError.quotaExceeded }
    } catch let error as WebIndexedDBError { throw error }
    catch let error as BrowserIOError { throw map(error) }
  }
  public func removeValue(forKey key:String) async throws { try await delete(key:key) }
}
public typealias WebIndexedDB<Value: EmbeddedCodable> = WebIndexedDBStore<Value>

#else
/// A synchronous value migration applied when a record's envelope version is
/// older than the store's current version. Migrations are ordered by their
/// `fromVersion` and can be chained (for example 1→2→3).
public struct WebIndexedDBMigration<Value: Codable> {
  public let fromVersion: Int
  public let toVersion: Int
  private let transform: (Value) throws -> Value

  public init(
    fromVersion: Int,
    toVersion: Int,
    transform: @escaping (Value) throws -> Value
  ) {
    precondition(toVersion > fromVersion, "IndexedDB migrations must advance the version")
    self.fromVersion = fromVersion
    self.toVersion = toVersion
    self.transform = transform
  }

  fileprivate func apply(_ value: Value) throws -> Value { try transform(value) }
}

private struct _IndexedDBEnvelope<Value: Codable>: Codable {
  let version: Int
  let value: Value
}

@MainActor public final class WebIndexedDBStore<Value: Codable> {
  public let databaseName: String
  public let objectStoreName: String
  public let version: Int
  public let quotaBytes: Int?
  private let migrations: [WebIndexedDBMigration<Value>]


  public init(
    databaseName: String,
    objectStoreName: String = "records",
    version: Int = 1,
    quotaBytes: Int? = nil,
    migrations: [WebIndexedDBMigration<Value>] = []
  ) {
    precondition(version >= 1 && version <= 2_147_483_647, "IndexedDB version must be between 1 and Int32.max")
    precondition(quotaBytes == nil || quotaBytes! > 0, "IndexedDB quota must be positive")
    self.databaseName = databaseName
    self.objectStoreName = objectStoreName
    self.version = version
    self.quotaBytes = quotaBytes
    self.migrations = migrations.sorted { $0.fromVersion < $1.fromVersion }
  }

  /// Loads and decodes a value. Older envelopes are migrated and rewritten
  /// before the value is returned, making migration durable across reloads.
  public func load(key: String) async throws -> Value? {
    try _validateWebIndexedDBNames(databaseName, objectStoreName)
    try _validateWebIndexedDBKey(key)
    guard let raw = try await readRaw(key: key) else { return nil }
    let decoder = _makeJSONDecoder()
    let envelope: _IndexedDBEnvelope<Value>
    do {
      envelope = try decoder.decode(_IndexedDBEnvelope<Value>.self, from: _data(raw))
    } catch {
      // Version 0 represented the initial, unwrapped Codable payload. Keep it
      // readable so an application can migrate its first schema release.
      do {
        let value = try decoder.decode(Value.self, from: _data(raw))
        let migrated = try migrate(value, from: 0)
        try await save(migrated, key: key)
        return migrated
      } catch let error as WebIndexedDBError {
        throw error
      } catch {
        throw WebIndexedDBError.encoding("Storage encoding failed")
      }
    }
    guard envelope.version <= version else {
      throw WebIndexedDBError.incompatibleVersion(found: envelope.version, expected: version)
    }
    let migrated = try migrate(envelope.value, from: envelope.version)
    if envelope.version != version {
      try await save(migrated, key: key)
    }
    return migrated
  }

  /// Encodes a versioned envelope and stores it under `key`.
  public func save(_ value: Value, key: String) async throws {
    try _validateWebIndexedDBNames(databaseName, objectStoreName)
    try _validateWebIndexedDBKey(key)
    let encoder = _makeJSONEncoder()
    do {
      let data = try encoder.encode(_IndexedDBEnvelope(version: version, value: value))
      let raw = String(decoding: _bytes(data), as: UTF8.self)
      try ensureQuota(replacing: [fallbackKey(key): raw])
      try await writeRaw(raw, key: key)
    } catch let error as WebIndexedDBError {
      throw error
    } catch {
      throw WebIndexedDBError.encoding("Storage encoding failed")
    }
  }

  /// Storage-shaped aliases for code that prefers key/value terminology.
  public func value(forKey key: String) async throws -> Value? {
    try await load(key: key)
  }

  public func setValue(_ value: Value, forKey key: String) async throws {
    try await save(value, key: key)
  }

  public func delete(key: String) async throws {
    try _validateWebIndexedDBNames(databaseName, objectStoreName)
    try _validateWebIndexedDBKey(key)
    _WebIndexedDBFallbackStorage.write(fallbackKey(key), nil, prefix: storePrefix)
  }

  public func removeValue(forKey key: String) async throws {
    try await delete(key: key)
  }

  /// Applies all writes to the deterministic native fallback as one commit.
  /// Encoding and quota checks happen before the shared dictionary is touched,
  /// so an error cannot leave a partially applied batch.
  public func transaction(_ mutations: [(key: String, value: Value?)]) async throws {
    try _validateWebIndexedDBNames(databaseName, objectStoreName)
    for mutation in mutations { try _validateWebIndexedDBKey(mutation.key) }
    let encoder = _makeJSONEncoder()
    var writes: [(String, String?)] = []
    for mutation in mutations {
      if let value = mutation.value {
        do {
          let data = try encoder.encode(_IndexedDBEnvelope(version: version, value: value))
          if let quotaBytes, data.count > quotaBytes { throw WebIndexedDBError.quotaExceeded }
          writes.append((fallbackKey(mutation.key), String(decoding: _bytes(data), as: UTF8.self)))
        } catch let error as WebIndexedDBError { throw error }
        catch { throw WebIndexedDBError.encoding("Storage encoding failed") }
      } else {
        writes.append((fallbackKey(mutation.key), nil))
      }
    }
    var replacements: [String: String?] = .init()
    for (key, value) in writes { replacements[key] = value }
    try ensureQuota(replacing: replacements)
    for (key, value) in writes { _WebIndexedDBFallbackStorage.write(key, value, prefix: storePrefix) }
  }

  private func migrate(_ value: Value, from initialVersion: Int) throws -> Value {
    var current = initialVersion
    var result = value
    while current < version {
      // Unversioned records predate the envelope and are the natural version
      // one representation. They can be adopted without a user migration;
      // later schema versions still require an explicit 0→N migration.
      if current == 0 && version == 1 {
        current = version
        break
      }
      guard let migration = migrations.first(where: { $0.fromVersion == current }) else {
        throw WebIndexedDBError.migrationRequired(from: current, to: version)
      }
      guard migration.toVersion <= version else {
        throw WebIndexedDBError.migrationRequired(from: current, to: version)
      }
      result = try migration.apply(result)
      current = migration.toVersion
    }
    return result
  }

  private func fallbackKey(_ key: String) -> String {
    _framedWebIndexedDBName(databaseName) + _framedWebIndexedDBName(objectStoreName) + _framedWebIndexedDBName(key)
  }

  private func readRaw(key: String) async throws -> String? {
    return _WebIndexedDBFallbackStorage.values[fallbackKey(key)]
  }

  private var storePrefix: String {
    _framedWebIndexedDBName(databaseName) + _framedWebIndexedDBName(objectStoreName)
  }

  private func writeRaw(_ value: String, key: String) async throws {
    _WebIndexedDBFallbackStorage.write(fallbackKey(key), value, prefix: storePrefix)
  }

  /// Throws when the store would exceed its quota after `replacements`. The store's running total is computed on
  /// first use; a check then costs the size of the replacements, not a scan of every record.
  private func ensureQuota(replacing replacements: [String: String?]) throws {
    guard let quotaBytes else { return }
    let prefix = storePrefix
    if _WebIndexedDBFallbackStorage.byteTotals[prefix] == nil {
      _WebIndexedDBFallbackStorage.byteTotals[prefix] = _WebIndexedDBFallbackStorage.values
        .filter { $0.key.hasPrefix(prefix) }.values.reduce(0) { $0 + $1.utf8.count }
    }
    var delta = 0
    for (key, value) in replacements {
      delta += (value?.utf8.count ?? 0) - (_WebIndexedDBFallbackStorage.values[key]?.utf8.count ?? 0)
    }
    // A change that does not grow the store is allowed even above a quota lowered since.
    if delta > 0, (_WebIndexedDBFallbackStorage.byteTotals[prefix] ?? 0) + delta > quotaBytes { throw WebIndexedDBError.quotaExceeded }
  }

}

/// Short spelling for applications that prefer the API name without the
/// implementation detail suffix.
public typealias WebIndexedDB<Value: Codable> = WebIndexedDBStore<Value>

private func _makeJSONEncoder() -> JSONEncoder { JSONEncoder() }
private func _makeJSONDecoder() -> JSONDecoder { JSONDecoder() }
private func _data(_ value: String) -> Data { Data(value.utf8) }
private func _bytes(_ value: Data) -> [UInt8] { Array(value) }

#endif
