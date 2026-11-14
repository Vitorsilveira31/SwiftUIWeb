@_spi(Renderer) import SwiftUIWebLocking

/// The item store behind `SecItem…`. Security.framework's calls are synchronous; IndexedDB and Web
/// Crypto are not. So `WebSecurity.unlock()` decrypts every item once into memory, the four calls
/// then answer from memory at once, and each change is encrypted and written in the background, in
/// the order the changes were made. Before the unlock finishes every call returns
/// `errSecInteractionNotAllowed`, the status the Keychain gives while a device is locked; when the
/// browser has no IndexedDB or Web Crypto they return `errSecNotAvailable`. `lock()` drops the
/// decrypted items from memory again.
final class _SecKeychain: Sendable {
  private struct State {
    var records: [_SecRecord] = []
    var unlocked = false
    var unavailable = false
    var nextID = 1
    /// Every id the store holds, readable or not (and each one added since): a new item takes an id outside it, so it
    /// never overwrites a stored record.
    var usedIDs: Set<Int> = []
    var unlocking: Task<Result<Void, WebSecurityError>, Never>?
    var persistence: Task<Void, Never>?
    var lastPersistenceError: WebSecurityError?
    /// Bumped by every `lock()`. A load that started under an older generation was overtaken by a
    /// lock and must not change anything when it finishes: IndexedDB and Web Crypto requests cannot
    /// be relied on to stop when a task is cancelled, so the lifecycle state decides instead.
    var generation: UInt64 = 0

    /// The status of a call made while the items are not in memory.
    var lockedStatus: OSStatus { unavailable ? errSecNotAvailable : errSecInteractionNotAllowed }
  }

  private enum Write { case save(_SecRecord), remove(String) }

  private let state = _Locked(State())
  let store: any WebSecretStore

  init(store: any WebSecretStore) { self.store = store }

  var isUnlocked: Bool { state.withLock { $0.unlocked } }
  var lastPersistenceError: WebSecurityError? { state.withLock { $0.lastPersistenceError } }

  func unlock() async throws(WebSecurityError) {
    let task = state.withLock { state -> Task<Result<Void, WebSecurityError>, Never>? in
      if state.unlocked { return nil }
      if let unlocking = state.unlocking { return unlocking }
      let store = self.store
      let generation = state.generation
      let task = Task { [self] () -> Result<Void, WebSecurityError> in
        let items: [(id: String, value: [UInt8])]
        do throws(WebSecurityError) { items = try await store.loadAll() } catch {
          self.state.withLock { state in
            guard state.generation == generation else { return }
            state.unlocking = nil
            if case .unavailable = error { state.unavailable = true }
          }
          return .failure(error)
        }
        var records: [_SecRecord] = []
        for item in items { if let record = _SecRecord.decode(id: item.id, from: item.value) { records.append(record) } }
        // Every stored id counts, read or not: a new item must not take the id of a record this version cannot read
        // and overwrite it.
        let storedIDs = items.compactMap { Int($0.id) }
        self.state.withLock { state in
          // Overtaken by lock(): the store stays locked and the decrypted items are dropped here.
          guard state.generation == generation else { return }
          state.records = records
          state.usedIDs = Set(storedIDs)
          // After the largest stored id, or from 1 when that is Int's end (2^31 - 1 in the browser build); an id taken
          // anyway is skipped when an item is added.
          let largest = storedIDs.max() ?? 0
          state.nextID = largest < Int.max ? largest + 1 : 1
          state.unlocked = true
          state.unavailable = false
          state.unlocking = nil
        }
        return .success(())
      }
      state.unlocking = task
      return task
    }
    guard let task else { return }
    try await task.value.get()
  }

  /// Waits for pending writes, then forgets the decrypted items; the calls answer
  /// `errSecInteractionNotAllowed` until the next `unlock()`. Swift does not let the memory that held
  /// them be overwritten, so this shortens how long plaintext stays reachable, nothing more.
  ///
  /// Once it returns the store stays locked: an `unlock()` that was still loading finishes without
  /// unlocking (its caller returns normally, and `isUnlocked` stays false), and only an `unlock()`
  /// called after this one can unlock again.
  func lock() async {
    await synchronize()
    state.withLock { state in
      state.generation &+= 1
      state.unlocking = nil
      state.records = []
      state.unlocked = false
    }
  }

  /// Waits until every change made so far is written.
  func synchronize() async {
    await state.withLock { $0.persistence }?.value
  }

  // MARK: SecItem operations

  func add(_ attributes: [String: SecValue]) -> (OSStatus, SecItemResult?) {
    if let refused = refusal(attributes) { return (refused, nil) }
    guard let value = attributes[kSecValueData]?.dataValue, attributes[kSecClass] != nil else { return (errSecParam, nil) }
    guard attributes.keys.allSatisfy({ _secStoredAttributes.contains($0) || _secQueryControls.contains($0) || $0 == kSecValueData }) else {
      return (errSecParam, nil)
    }
    var stored = attributes.filter { _secStoredAttributes.contains($0.key) }
    if stored[kSecAttrAccessible] == nil { stored[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked }
    let outcome = state.withLock { state -> (OSStatus, _SecRecord?) in
      guard state.unlocked else { return (state.lockedStatus, nil) }
      // The next id no stored record holds. A full id space (2^31 items in the browser) cannot be reached: an item is
      // at least its record's bytes, and the store keeps far less.
      var candidate = state.nextID
      var tried = 0
      while state.usedIDs.contains(candidate), tried < state.usedIDs.count + 1 {
        candidate = candidate < Int.max ? candidate + 1 : 1
        tried += 1
      }
      guard !state.usedIDs.contains(candidate) else { return (errSecAllocate, nil) }
      let record = _SecRecord(id: String(candidate), attributes: stored, value: value)
      guard !state.records.contains(where: { $0.identity == record.identity }) else { return (errSecDuplicateItem, nil) }
      // Refused now rather than accepted and then dropped by the store, which keeps at most a megabyte per item.
      guard record.encoded().count <= _SecRecord.byteLimit else { return (errSecAllocate, nil) }
      // Wrapping is not reachable from real use (2^31 items) and must not trap on a stored id near the end.
      state.nextID = candidate < Int.max ? candidate + 1 : 1
      state.usedIDs.insert(candidate)
      state.records.append(record)
      return (errSecSuccess, record)
    }
    guard let record = outcome.1 else { return (outcome.0, nil) }
    persist([.save(record)])
    return (errSecSuccess, result([record], for: attributes))
  }

  func copyMatching(_ query: [String: SecValue]) -> (OSStatus, SecItemResult?) {
    if let refused = refusal(query) ?? classMissing(query) { return (refused, nil) }
    let outcome = state.withLock { state -> (OSStatus, [_SecRecord]) in
      state.unlocked ? (errSecSuccess, state.records.filter { $0.matches(query) }) : (state.lockedStatus, [])
    }
    guard outcome.0 == errSecSuccess else { return (outcome.0, nil) }
    let matches = outcome.1
    guard !matches.isEmpty else { return (errSecItemNotFound, nil) }
    return (errSecSuccess, result(matches, for: query))
  }

  func update(_ query: [String: SecValue], _ changes: [String: SecValue]) -> OSStatus {
    if let refused = refusal(query) ?? classMissing(query) ?? refusal(changes) { return refused }
    guard changes[kSecClass] == nil, !changes.isEmpty,
          changes.keys.allSatisfy({ _secStoredAttributes.contains($0) || $0 == kSecValueData }) else { return errSecParam }
    let outcome = state.withLock { state -> (OSStatus, [_SecRecord]) in
      guard state.unlocked else { return (state.lockedStatus, []) }
      let indices = state.records.indices.filter { state.records[$0].matches(query) }
      guard !indices.isEmpty else { return (errSecItemNotFound, []) }
      var updated = state.records
      for index in indices {
        for (key, value) in changes where key != kSecValueData { updated[index].attributes[key] = value }
        if let data = changes[kSecValueData]?.dataValue { updated[index].value = data }
      }
      let identities = updated.map { $0.identity }
      guard Set(identities.map { $0.map { $0 ?? .bool(false) } }).count == identities.count else { return (errSecDuplicateItem, []) }
      guard indices.allSatisfy({ updated[$0].encoded().count <= _SecRecord.byteLimit }) else { return (errSecAllocate, []) }
      state.records = updated
      return (errSecSuccess, indices.map { updated[$0] })
    }
    if outcome.0 == errSecSuccess { persist(outcome.1.map { .save($0) }) }
    return outcome.0
  }

  func delete(_ query: [String: SecValue]) -> OSStatus {
    if let refused = refusal(query) ?? classMissing(query) { return refused }
    let outcome = state.withLock { state -> (OSStatus, [String]) in
      guard state.unlocked else { return (state.lockedStatus, []) }
      let removed = state.records.filter { $0.matches(query) }.map { $0.id }
      guard !removed.isEmpty else { return (errSecItemNotFound, []) }
      // One pass over the records against a set of ids, not a scan of the removed list for each record.
      let removedIDs = Set(removed)
      state.records.removeAll { removedIDs.contains($0.id) }
      return (errSecSuccess, removed)
    }
    if outcome.0 == errSecSuccess { persist(outcome.1.map { .remove($0) }) }
    return outcome.0
  }

  // MARK: Helpers

  /// A query names its item class, as Apple's keychain requires (`errSecParam` otherwise). Without the check an empty
  /// query would match every item: `SecItemDelete([:])` would empty the keychain.
  private func classMissing(_ query: [String: SecValue]) -> OSStatus? {
    query[kSecClass] == nil ? errSecParam : nil
  }

  /// Session credentials and synchronization have no honest browser equivalent.
  private func refusal(_ dictionary: [String: SecValue]) -> OSStatus? {
    if dictionary[kSecClass] == kSecClassInternetPassword || dictionary[kSecAttrServer] != nil { return errSecUnimplemented }
    if dictionary[kSecAttrSynchronizable]?.boolValue == true { return errSecUnimplemented }
    if let itemClass = dictionary[kSecClass], itemClass != kSecClassGenericPassword { return errSecParam }
    return nil
  }

  private func result(_ records: [_SecRecord], for query: [String: SecValue]) -> SecItemResult? {
    let wantsData = query[kSecReturnData]?.boolValue == true
    let wantsAttributes = query[kSecReturnAttributes]?.boolValue == true
    guard wantsData || wantsAttributes, let first = records.first else { return nil }
    if query[kSecMatchLimit] == kSecMatchLimitAll {
      return .items(records.map { $0.dictionary(includingData: wantsData) })
    }
    return wantsAttributes ? .attributes(first.dictionary(includingData: wantsData)) : .data(first.value)
  }

  private func persist(_ writes: [Write]) {
    let store = self.store
    state.withLock { state in
      let previous = state.persistence
      state.persistence = Task { [self] in
        await previous?.value
        for write in writes {
          do throws(WebSecurityError) {
            switch write {
            case .save(let record): try await store.save(record.encoded(), id: record.id)
            case .remove(let id): try await store.remove(id: id)
            }
          } catch {
            self.state.withLock { $0.lastPersistenceError = error }
          }
        }
      }
    }
  }
}
