@_spi(Renderer) import SwiftUIWebTransferable

#if canImport(Observation)
// Re-export the standard library's observation macro when it is available.
// This keeps `@Observable` source-compatible for SwiftUIWeb applications
// without making the core depend on Observation on WASI/Embedded toolchains
// that do not ship it.
@_exported import Observation
#endif

// Native builds use Combine's `ObservableObject`, `ObservableObjectPublisher` and `Published`: the types an application
// that also imports Foundation sees, so they are never declared twice. Embedded keeps SwiftUIWeb's own.

public protocol DynamicProperty {}

/// Renderer-only identity for a state source. The leading underscore is
/// intentional: this is an implementation detail used by the Fiber/browser
/// targets and is not part of the SwiftUI-facing API. A source ID is stable
/// for the lifetime of the state box and can be stored as a compact integer in
/// the renderer's arena instead of retaining a closure per dependency edge.
///
/// It is a `UInt64`, not a wrapper of one: Embedded Swift emits its own copy of the `Dictionary`/`Set` code for every
/// key type, and the graph's tables keyed by a source then share the copy its owner-token tables already use.
@_spi(Renderer) public typealias _StateSourceID = UInt64

extension UInt64 {
  @_spi(Renderer) public init(rawValue: UInt64) { self = rawValue }
  @_spi(Renderer) public var rawValue: UInt64 { self }

  /// Reserved source for inherited environment reads. State boxes receive
  /// small monotonically increasing identifiers, so this value cannot alias a
  /// normal state source during a renderer lifetime.
  @_spi(Renderer) public static var environment: UInt64 { .max }
}

/// A table of values by name, each kept in an object of its own. Embedded Swift emits the hashed-collection code once per
/// key type and value layout: every `_ReferenceTable` is a table of references and shares one copy, where a table of
/// the value itself would carry its own. For values written now and then (measurements, caches, running tasks): a
/// write allocates the object, a read does not.
package struct _ReferenceTable<Value> {
  private final class Box {
    let value: Value
    init(_ value: Value) { self.value = value }
  }
  private var boxes: [String: Box] = .init()

  package init() {}

  package subscript(key: String) -> Value? {
    get { boxes[key]?.value }
    set { boxes[key] = newValue.map { Box($0) } }
  }

  package var count: Int { boxes.count }
  package var keys: [String] { Array(boxes.keys) }

  package func forEachValue(_ body: (Value) -> Void) {
    for box in boxes.values { body(box.value) }
  }

  package mutating func removeAll(keepingCapacity: Bool = false) { boxes.removeAll(keepingCapacity: keepingCapacity) }

  package mutating func removeValues(where shouldRemove: (String) -> Bool) {
    for key in boxes.keys where shouldRemove(key) { boxes.removeValue(forKey: key) }
  }
}

/// Cancellation token for an internal state-source subscription. StateStore
/// owns the callback table; disposing the token removes one source edge
/// without requiring a reference cycle between a state box and a Fiber tree.
@MainActor @_spi(Renderer) public final class _StateSubscription {
  private var cancellation: (() -> Void)?

  public init(_ cancellation: @escaping () -> Void) {
    self.cancellation = cancellation
    _RuntimeMemoryMetrics.recordStateSubscriptionInit()
  }

  public func cancel() {
    guard let cancellation else { return }
    self.cancellation = nil
    cancellation()
  }

  isolated deinit {
    _RuntimeMemoryMetrics.recordStateSubscriptionDeinit()
    cancel()
  }
}

/// Dependency-free publisher used by `ObservableObject`.  Keeping this in
/// Core avoids any external reactive-framework or Foundation dependency while
/// preserving the familiar SwiftUI `objectWillChange.send()` entry point.
public final class ObservableObjectPublisher {
  private var observers: [() -> Void] = []

  public init() {}

  @_spi(Renderer) public func subscribe(_ observer: @escaping () -> Void) {
    observers.append(observer)
  }

  public func send() {
    let callbacks = observers
    for callback in callbacks { callback() }
  }
}

/// Structured Observation telemetry exposed to renderer tests and host
/// diagnostics. The counters describe the lifetime of one StateStore; the
/// dependency snapshot is the source/owner classification at the
/// instant the value is read.
@_spi(Renderer) public struct _StateStoreObservationDiagnostics: Sendable, Equatable {
  public let accessCount: Int
  public let invalidationCount: Int
  public let coalescedInvalidationCount: Int
  public let teardownCount: Int
  public let isDisposed: Bool
  public let dependencies: _DependencyDiagnostics

  public init(
    accessCount: Int = 0,
    invalidationCount: Int = 0,
    coalescedInvalidationCount: Int = 0,
    teardownCount: Int = 0,
    isDisposed: Bool = false,
    dependencies: _DependencyDiagnostics = .init(
      hasDirtyStructural: false,
      hasObservation: false,
      uniqueStructuralOwners: [],
      observationOwners: []
    )
  ) {
    self.accessCount = accessCount
    self.invalidationCount = invalidationCount
    self.coalescedInvalidationCount = coalescedInvalidationCount
    self.teardownCount = teardownCount
    self.isDisposed = isDisposed
    self.dependencies = dependencies
  }

  public var plan: _InvalidationPlan { dependencies.plan }
}

/// The Embedded source-to-StateStore index is strong by design (weak
/// references are not available in Embedded Swift). Exposing its shape lets
/// lifecycle tests prove that `_dispose()` removes every strong index edge.
@_spi(Renderer) public struct _PublishedObservationIndexDiagnostics: Sendable, Equatable {
  public let sourceCount: Int
  public let storeLinks: Int
  public init(sourceCount: Int = 0, storeLinks: Int = 0) {
    self.sourceCount = sourceCount
    self.storeLinks = storeLinks
  }
}

public protocol ObservableObject: AnyObject {}

fileprivate protocol _PublishedObservationRegistration: AnyObject {
  func _removeObserver(_ store: StateStore)
}

#if !hasFeature(Embedded)
private enum ObservableObjectRuntime {
  private final class Registry: @unchecked Sendable {
    var publishers: [ObjectIdentifier: ObservableObjectPublisher] = .init()
  }
  // Guarded by `lock`.
  private static let registry = Registry()

  // Native hosts may evaluate independent trees on several threads.
  private static let lock = _RuntimeLock()

  static func publisher(for object: AnyObject) -> ObservableObjectPublisher {
    let identifier = ObjectIdentifier(object)
    return lock.withLock {
      if let publisher = registry.publishers[identifier] { return publisher }
      let publisher = ObservableObjectPublisher()
      registry.publishers[identifier] = publisher
      return publisher
    }
  }
}
#endif

public extension ObservableObject {
  /// A conforming model gets a stable publisher automatically. Models can
  /// still declare their own `objectWillChange` when they need custom
  /// ownership or compatibility with another publisher implementation.
  var objectWillChange: ObservableObjectPublisher {
    #if hasFeature(Embedded)
    // Embedded models use the generated publisher bridge below. Keep the
    // familiar API available without requiring protocol metadata in the WASM
    // link, where the standard Observation runtime is absent.
    ObservableObjectPublisher()
    #else
    ObservableObjectRuntime.publisher(for: self)
    #endif
  }
}

/// Lightweight property-level observation for models that use `@Published`.
/// The API is intentionally small and does not pull an external reactive
/// framework or Foundation into SwiftUIWeb's core. Embedded Swift cannot form
/// the enclosing-instance key-path that such property-publishing mechanisms
/// need, so writes notify the
/// active Fiber stores through a framework-owned bridge.
#if hasFeature(Embedded)
@MainActor
#endif
@propertyWrapper public struct Published<Value> {
  /// The `projectedValue` (`$model.value`). Apple's publisher is a struct, so this is a value
  /// that shares its observers with every copy.
  public struct Publisher {
    public typealias Output = Value
    public typealias Failure = Never
    private final class Observers {
      var callbacks: [(Value) -> Void] = []
    }
    private let observers = Observers()
    init() {}
    @_spi(Renderer) public func subscribe(_ observer: @escaping (Value) -> Void) { observers.callbacks.append(observer) }
    @_spi(Renderer) public func send(_ value: Value) {
      guard !observers.callbacks.isEmpty else { return }
      let callbacks = observers.callbacks
      for callback in callbacks { callback(value) }
    }
  }

  fileprivate final class Storage: _PublishedObservationRegistration {
    private var storedValue: Value?
    /// True when writing `newValue` would not change an already-initialized value.
    func isUnchanged(by newValue: Value) -> Bool {
      guard let isEqual, let storedValue else { return false }
      return isEqual(storedValue, newValue)
    }
    var value: Value {
      get {
        guard let storedValue else { fatalError("Published value was read before initialization") }
        return storedValue
      }
      set { storedValue = newValue }
    }
    let publisher: Publisher
    /// Set for `Equatable` values: an equal write invalidates nothing.
    var isEqual: ((Value, Value) -> Bool)?
#if hasFeature(Embedded)
    /// Each lowered observable member gets its own source token.  The token
    /// is the Embedded equivalent of ObservationRegistrar's (model, member)
    /// identity; the dependency graph owns the actual owner edges.
    let observationSource: _StateSourceID
    let observationMemberID: UInt32
    private var observingStores: [StateStore] = []
#endif
    init(_ value: Value, memberID: UInt32 = 0) {
      storedValue = value
      publisher = Publisher()
#if hasFeature(Embedded)
      observationMemberID = memberID
      observationSource = _StateSourceID(rawValue: StateStore._allocateEmbeddedObservationSource(memberID: memberID))
#endif
      _RuntimeMemoryMetrics.recordStateStorageInit()
    }
    init(memberID: UInt32 = 0) {
      storedValue = nil
      publisher = Publisher()
#if hasFeature(Embedded)
      observationMemberID = memberID
      observationSource = _StateSourceID(rawValue: StateStore._allocateEmbeddedObservationSource(memberID: memberID))
#endif
      _RuntimeMemoryMetrics.recordStateStorageInit()
    }
    deinit {
      _RuntimeMemoryMetrics.recordStateStorageDeinit()
    }

#if hasFeature(Embedded)
    @MainActor func recordObservation(in store: StateStore) {
      let source = observationSource
      if !observingStores.contains(where: { $0 === store }) {
        observingStores.append(store)
        store._retainPublishedObservation(self)
      }
      store._recordPublishedObservation(source)
    }

    @MainActor func notifyObservers() {
      let source = observationSource
      for store in observingStores {
        store._publishedObservationDidChange(source)
      }
    }

    func _removeObserver(_ store: StateStore) {
      observingStores.removeAll { $0 === store }
    }
#else
    func _removeObserver(_ store: StateStore) {}
#endif
  }

  private let storage: Storage
  public init(wrappedValue: Value) { storage = Storage(wrappedValue) }
  public init(wrappedValue: Value) where Value: _WriteEquatable {
    storage = Storage(wrappedValue)
    storage.isEqual = { $0 == $1 }
  }
  /// Renderer SPI. The source lowerer emits `memberID` and adds
  /// `@_spi(Renderer) import SwiftUIWeb` to the lowered file.
  @_spi(Renderer) public init(wrappedValue: Value, memberID: UInt32) {
    storage = Storage(wrappedValue, memberID: memberID)
  }
  @_spi(Renderer) public init(wrappedValue: Value, memberID: UInt32) where Value: _WriteEquatable {
    storage = Storage(wrappedValue, memberID: memberID)
    storage.isEqual = { $0 == $1 }
  }
  /// Allows lowered `@Observable` members whose initial value is assigned by
  /// the model's initializer, rather than at the property declaration.
  @_spi(Renderer) public init(memberID: UInt32) { storage = Storage(memberID: memberID) }
  @_spi(Renderer) public init(memberID: UInt32) where Value: _WriteEquatable {
    storage = Storage(memberID: memberID)
    storage.isEqual = { $0 == $1 }
  }
#if !hasFeature(Embedded)
  @available(*, unavailable, message: "@Published is only available on properties of classes")
#endif
  public var wrappedValue: Value {
    get {
#if hasFeature(Embedded)
      if let store = StateRuntime.scope?.store { storage.recordObservation(in: store) }
#endif
      return storage.value
    }
    nonmutating set { store(newValue) }
    // An in-place update (`value += 1`, `value.append(_:)`) reads the value without making the rendering view an observer
    // of it. Through the getter, the view that performs the update would observe its own write and render again, and a
    // view that creates an object whose initializer bumps a published counter would render, create the object and
    // invalidate itself forever (the browser media player).
    nonmutating _modify {
      var current = storage.value
      yield &current
      store(current)
    }
  }

  /// The one write path of the setter and of in-place updates. Outside Embedded `wrappedValue` is unavailable (the
  /// enclosing-instance subscript below is the native spelling), so the accessors cannot write through it.
  private func store(_ newValue: Value) {
#if hasFeature(Embedded)
    let unchanged = storage.isUnchanged(by: newValue)
#endif
    storage.value = newValue
    storage.publisher.send(newValue)
#if hasFeature(Embedded)
    if !unchanged { storage.notifyObservers() }
#endif
  }
  public var projectedValue: Publisher { storage.publisher }

  #if !hasFeature(Embedded)
  /// Native class-bound models get SwiftUI-style automatic invalidation when
  /// a published property is written. Embedded Swift cannot form this
  /// enclosing-instance key path, so its source-lowered models use the bridge
  /// above instead.
  public static subscript<EnclosingSelf: ObservableObject>(
    _enclosingInstance instance: EnclosingSelf,
    wrapped _: ReferenceWritableKeyPath<EnclosingSelf, Value>,
    storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Published<Value>>
  ) -> Value {
    get { instance[keyPath: storageKeyPath].storage.value }
    set {
      let property = instance[keyPath: storageKeyPath]
      let unchanged = property.storage.isUnchanged(by: newValue)
      property.storage.value = newValue
      property.storage.publisher.send(newValue)
      if !unchanged { instance.objectWillChange.send() }
    }
  }
  #endif
}

@MainActor @preconcurrency @propertyWrapper public struct EnvironmentObject<ObjectType: AnyObject>: DynamicProperty {
  // See `Environment`: the object resolved for the view's last update stays
  // available to its actions and tasks after the render pass ends.
  private let resolution = _EnvironmentResolution()
  @MainActor @preconcurrency public init() {}
  @MainActor @preconcurrency public var wrappedValue: ObjectType {
    let inRender = StateRuntime.scope != nil
    if inRender { StateRuntime.scope?.store._recordEnvironmentRead() }
    guard let object = resolution.first(inRender: inRender, { $0._storedValue(EnvironmentObjectKey<ObjectType>.self) }) else {
      fatalError("No EnvironmentObject supplied")
    }
    if inRender { StateRuntime.scope?.store.observe(object) }
    return object
  }
  @MainActor @preconcurrency public var projectedValue: ObjectType { wrappedValue }
}

enum EnvironmentObjectKey<ObjectType: AnyObject>: EnvironmentKey {
  static var defaultValue: ObjectType { fatalError("No EnvironmentObject supplied") }
}

@MainActor package final class StateStore {
#if hasFeature(Embedded)
  // Property wrappers own their observation links. This static is only a
  // constant-initialized allocator and does not need a lazy global lookup.
  nonisolated private static let nextEmbeddedObservationSource = _Locked<UInt64>(0x8000_0000_0000_0001)

  fileprivate nonisolated static func _allocateEmbeddedObservationSource(memberID: UInt32) -> UInt64 {
    let source = nextEmbeddedObservationSource.withLock { next -> UInt64 in
      precondition(next < UInt64.max, "Embedded observation source space exhausted")
      defer { next &+= 1 }
      return next
    }
    // Keep the member ID in the call site for diagnostics and future registry
    // introspection without encoding it into the source identity itself.
    _ = memberID
    return source
  }

#endif

  /// This store's dependency edges and dirty queues.
  /// Like the existing renderer, StateStore requires serialized access. Its
  /// historical unchecked Sendable conformance is not a cross-thread lock.
  @_spi(Renderer) public let _dependencies = _DependencyGraph()

  /// The compact DOM ids of this document's identity paths (`_FiberPath._compactID`).
  @_spi(Renderer) public let _compactPathIDs = _CompactPathIDRegistry()
  private var storage: [String: _StateStoreEntry] = .init()
  // A value view can first read a lazily-adopted @State property from a
  // conditional branch.  The old path-only lookup could then reuse another
  // same-typed property whose slot happened to be allocated earlier in that
  // render pass.  Keep the box's assigned slot alongside the path table so a
  // box that has already been adopted can never alias an unrelated property.
  private var keysByStateBox: [ObjectIdentifier: String] = .init()
  private var observedValues = _TypedChangeHistory<String>()
  private var observedKeys: Set<String> = []
  private var observedObjects: Set<ObjectIdentifier> = []
  // Keep the source assigned to each observed object so every render pass can
  // re-attribute that model to the current owner.  A model is subscribed only
  // once, but it may be read by several disjoint AnyView owners; retaining the
  // source mapping prevents the first reader from accidentally owning all
  // later invalidations.
  private var observedObjectSources: [ObjectIdentifier: _StateSourceID] = .init()
  private var publisherSubscriptions: [ObservableObjectPublisher] = []
#if hasFeature(Embedded)
  private var publishedObservationRegistrations: [_PublishedObservationRegistration] = []
  #endif
  private var pendingPublishedObservationSources: Set<_StateSourceID> = []

  // Effects SwiftUI runs after a view update rather than while a body is
  // evaluated (`onChange`). During a Fiber pass they queue here and run once
  // the outermost pass has committed, so the state they write is an ordinary
  // invalidation that routes to its readers instead of a write during
  // rendering that can only fall back to re-rendering the root. Outside a
  // pass (static rendering, tests) they run immediately.
  private var effectDeferralDepth = 0
  private var deferredEffects: [() -> Void] = []
  // Owner tokens whose paths survive in the dependency graph after their
  // Fiber disappears. A targeted pass can retire these edges atomically with
  // the replacement owners it reads; a full pass resets the graph anyway.
  private var pendingDependencyOwnerReplacements: Set<UInt64> = []
  private var invalidationHandler: (() -> Void)?
  private var pendingAnimationCSS: String?
  /// The transaction of the state changes the next render shows, kept from the moment they happened until they are
  /// published (`_takeAnimationTransactionCSS`).
  package private(set) var _commitTransaction: Transaction?
  /// What Swift animates itself keeps between renders, by fiber path (`Animator.swift`).
  var _animatorValues = _TypedValueStorage<String>()
  /// The layouts the page measured for the texts a `TextRenderer` draws, by fiber path (`TextRenderer.swift`).
  var _textLayouts = _ReferenceTable<_MeasuredTextLayout>()
  /// The frames in the window the page measured for anchors and text layouts, by path (`_measureWindowFrame`).
  var _windowFrames = _ReferenceTable<CGRect>()
  private var disposed = false
  private var observationAccessCount = 0
  private var observationInvalidationCount = 0
  private var observationCoalescedInvalidationCount = 0
  private var observationTeardownCount = 0

  @_spi(Renderer) public func _takeAnimationTransactionCSS() -> String? {
    defer { pendingAnimationCSS = nil; _commitTransaction = nil }
    return pendingAnimationCSS
  }
  // State sources and subscribers are renderer-owned bookkeeping. The source
  // ID is assigned once to a StateBox and survives all value-view copies.
  private var nextSourceID: UInt64 = 1
  private struct Subscriber {
    let source: _StateSourceID
    let id: UInt64
    let callback: () -> Void
  }
  // A contiguous subscriber list avoids one dictionary allocation per source.
  // Source fan-out is normally tiny (one or a few controls), so a linear
  // removal is cheaper and more Embedded-friendly than nested hash tables.
  private var subscribers: [Subscriber] = []
  private var nextSubscriberID: UInt64 = 1
  /// The task a `.task` modifier started, by key, with the `id` it was started for.
  private var runningTasks = _ReferenceTable<(task: Task<Void, Never>, id: String?)>()

  isolated deinit {
    _dispose()
    _RuntimeMemoryMetrics.recordStateStoreDeinit()
    _RuntimeMemoryMetrics.clearStateStoreShape()
  }

  /// Ends this store's ownership of callbacks, tasks and observation routes.
  ///
  /// Embedded hosts cannot rely on `deinit` to break the Fiber callback cycle:
  /// the callback itself may retain the tree for the lifetime of the browser
  /// session. Hosts that replace a root tree should call this method before
  /// releasing the old tree. It is idempotent and must be called while the
  /// renderer is quiescent.
  @_spi(Renderer) public func _dispose() {
    guard !disposed else { return }
    disposed = true
    observationTeardownCount += 1
    invalidationHandler = nil
#if hasFeature(Embedded)
    for registration in publishedObservationRegistrations {
      registration._removeObserver(self)
    }
    publishedObservationRegistrations.removeAll(keepingCapacity: false)
#endif
    pendingPublishedObservationSources.removeAll(keepingCapacity: false)
    pendingDependencyOwnerReplacements.removeAll(keepingCapacity: false)
    // Retire graph edges before detaching Swift boxes. This keeps a disposed
    // store diagnostically empty even if it remains alive until the final
    // Fiber reference is released.
    _dependencies.reset()
    for entry in storage.values {
      entry._detach()
    }
    storage.removeAll(keepingCapacity: false)
    keysByStateBox.removeAll(keepingCapacity: false)
    observedValues.removeAll(keepingCapacity: false)
    observedKeys.removeAll(keepingCapacity: false)
    observedObjects.removeAll(keepingCapacity: false)
    observedObjectSources.removeAll(keepingCapacity: false)
    publisherSubscriptions.removeAll(keepingCapacity: false)
    subscribers.removeAll(keepingCapacity: false)
    runningTasks.forEachValue { $0.task.cancel() }
    runningTasks.removeAll(keepingCapacity: false)
    recordRuntimeMemoryShape()
  }
  package func box<Value>(_ key: String, default value: @autoclosure () -> Value) -> StateBox<Value> {
    if let existing = storage[key] as? StateBox<Value> {
      attach(existing)
      return existing
    }
    let created = StateBox(value())
    attach(created)
    storage[key] = created
    keysByStateBox[ObjectIdentifier(created)] = key
    return created
  }

  /// Retires path-scoped storage when a semantic Fiber subtree leaves the
  /// mounted tree. State keys are shared across value-view refreshes, so they
  /// must be removed only at the Fiber lifetime boundary, not when an owner
  /// token is refreshed during an ordinary render.
  @_spi(Renderer) public func _releaseStateScope(atPathPrefix pathPrefix: String) {
    _releaseStateScopes(atPathPrefixes: [pathPrefix])
  }

  /// Retires several scopes in one pass over the store. A key belongs to scope `P` when it starts with `P` followed by
  /// `#`; each of the key's `#` prefixes is looked up among the scopes, so a subtree that leaves the tree costs one pass
  /// over the keys instead of one per Fiber, each comparing every key with that Fiber's path.
  @_spi(Renderer) public func _releaseStateScopes(atPathPrefixes pathPrefixes: [String]) {
    guard !disposed, !pathPrefixes.isEmpty else { return }
    // Sorted, and searched by halving: a prefix of a key is looked up without making a `String` of it, and without the
    // `Set<Substring>` whose hashed-collection code Embedded Swift would emit for this one use.
    let scopes = pathPrefixes.sorted()
    func isScope(_ prefix: Substring) -> Bool {
      var low = 0, high = scopes.count
      while low < high {
        let middle = (low + high) / 2
        if scopes[middle] < prefix { low = middle + 1 } else { high = middle }
      }
      return low < scopes.count && scopes[low] == prefix
    }
    func belongsToScope(_ key: String) -> Bool {
      var start = key.startIndex
      while let separator = key[start...].firstIndex(of: "#") {
        if isScope(key[..<separator]) { return true }
        start = key.index(after: separator)
      }
      return false
    }

    let removedKeys = storage.keys.filter(belongsToScope)
    for key in removedKeys {
      storage.removeValue(forKey: key)?._detach()
    }
    if !removedKeys.isEmpty {
      let removedKeySet = Set(removedKeys)
      let staleBoxes = keysByStateBox.compactMap { box, key in
        removedKeySet.contains(key) ? box : nil
      }
      for box in staleBoxes { keysByStateBox.removeValue(forKey: box) }
    }

    // What the motion engine keeps by compact path (animated values, measured text, window frames) leaves with its view.
    for key in _animatorValues.keys where belongsToScope(key) { _animatorValues.removeValue(for: key) }
    _textLayouts.removeValues(where: belongsToScope)
    _windowFrames.removeValues(where: belongsToScope)

    let rememberedKeys = observedKeys.filter(belongsToScope)
    for key in rememberedKeys {
      observedKeys.remove(key)
      observedValues.removeValue(for: key)
    }
    for key in runningTasks.keys where belongsToScope(key) { cancelTask(key: key) }
    recordRuntimeMemoryShape()
  }

  /// Adopts a state box that was created while evaluating an application
  /// value. SwiftUI constructs property wrappers before `body` is evaluated;
  /// the first Fiber pass therefore needs to attach those boxes to the
  /// tree's identity store lazily. Returning the existing box on subsequent
  /// passes preserves state when a fresh view value is used for reconciliation.
  func register<Value>(
    _ candidate: StateBox<Value>,
    key: String,
    reuseMatchingSlot: Bool = false
  ) -> StateBox<Value> {
    let box = registeredEntry(candidate, key: key, reuseMatchingSlot: reuseMatchingSlot) { $0 is StateBox<Value> }
    // SAFETY: `registeredEntry` returns `candidate` or an entry `isBox` accepted, a `StateBox<Value>` either way.
    let registered = unsafeDowncast(box, to: StateBox<Value>.self)
    #if DEBUG
    // A box entering the store for the first time takes the value an earlier page saved under its key.
    if registered === candidate, !_StateSnapshots.pending.isEmpty, let key = keysByStateBox[ObjectIdentifier(registered)],
      let saved = _StateSnapshots.pending.removeValue(forKey: _StateSnapshots.stableKey(key))
    {
      registered._restore(tag: saved.tag, text: saved.text)
    }
    #endif
    attach(registered)
    return registered
  }

  /// The non-generic part of `register`, so it is not compiled once per state type: the entry to use for `candidate`,
  /// recorded under its key. `isBox` tells whether an entry holds the candidate's type.
  private func registeredEntry(
    _ candidate: _StateStoreEntry, key: String, reuseMatchingSlot: Bool, isBox: (_StateStoreEntry) -> Bool
  ) -> _StateStoreEntry {
    let candidateID = ObjectIdentifier(candidate)
    if let assignedKey = keysByStateBox[candidateID],
       let existing = storage[assignedKey], isBox(existing) {
      return existing
    }
    if let occupied = storage[key] {
      if reuseMatchingSlot, isBox(occupied) {
        // The fresh wrapper's candidate is discarded when StateStorage adopts
        // this existing box. Do not keep its ObjectIdentifier: temporary box
        // addresses can be reused by later @State values, which would map an
        // unrelated wrapper back to this slot.
        return occupied
      }
      if occupied === candidate {
        keysByStateBox[candidateID] = key
        return occupied
      }
      // A path slot is only a fallback for a fresh wrapper.  If another
      // property already owns it, preserve both boxes under a deterministic
      // collision suffix instead of silently aliasing their values.
      var uniqueKey = key
      var suffix = 1
      while storage[uniqueKey] != nil {
        uniqueKey = "\(key)@state\(suffix)"
        suffix += 1
      }
      storage[uniqueKey] = candidate
      keysByStateBox[candidateID] = uniqueKey
      return candidate
    }
    storage[key] = candidate
    keysByStateBox[candidateID] = key
    return candidate
  }

  #if DEBUG
  /// Every state of this store that has a text form, by key, for `_StateSnapshots.text(of:)`.
  func _snapshotEntries() -> [(key: String, tag: String, text: String)] {
    storage.compactMap { key, entry in entry._snapshot().map { (key, $0.tag, $0.text) } }
  }
  #endif

  private func attach<Value>(_ box: StateBox<Value>) {
    if box.sourceID == nil {
      box.sourceID = _StateSourceID(rawValue: nextSourceID)
      nextSourceID &+= 1
    }
    #if hasFeature(Embedded)
    // Embedded has no weak references. Capture only the already-assigned source
    // and the store; this closure is detached
    // when the state store releases its boxes.
    let source = box.sourceID!
    box.onRead = { self.recordRead(source) }
    box.onChange = { self.sourceDidChange(source) }
    #else
    box.onRead = { [weak self, weak box] in
      guard let self, let box, let source = box.sourceID else { return }
      self.recordRead(source)
    }
    box.onChange = { [weak self, weak box] in
      guard let self, let box, let source = box.sourceID else { return }
      self.sourceDidChange(source)
    }
    #endif
  }

  fileprivate func _reattach<Value>(_ box: StateBox<Value>) {
    attach(box)
  }

  /// The dependency graph owns pending reads, leaf credits and the committed edges.
  /// Callers only supply source/owner identities while evaluating typed views.
  @_spi(Renderer) public func _beginRenderPass() {
    guard !disposed else { return }
    pendingDependencyOwnerReplacements.removeAll(keepingCapacity: true)
    _dependencies.beginPass(.root)
  }
  @_spi(Renderer) public func _beginSupplementalRenderPass() {
    guard !disposed else { return }
    _dependencies.beginPass(.supplemental)
  }
  @_spi(Renderer) public func _beginSubtreeRenderPass(replacing owners: Set<UInt64>) {
    guard !disposed else { return }
    var replacements = owners
    replacements.formUnion(pendingDependencyOwnerReplacements)
    pendingDependencyOwnerReplacements.removeAll(keepingCapacity: true)
    _dependencies.beginPass(.subtree, replacing: replacements)
  }

  /// Keeps what `owners` read when they last ran through the current pass: a subtree the render reused without
  /// running its bodies reads nothing in it, and its state must still reach it.
  @_spi(Renderer) public func _keepOwnerReads(_ owners: [UInt64]) {
    guard !disposed, !owners.isEmpty else { return }
    _dependencies.keepOwners(owners)
  }

  /// Whether `owner` read something that changed since the last pass (a reused render would miss the change).
  @_spi(Renderer) public func _ownerIsDirty(_ owner: UInt64) -> Bool {
    guard !disposed else { return true }
    return _dependencies.ownerIsDirty(owner)
  }

  /// Includes detached readers in the next subtree replacement transaction.
  /// Fiber calls this only after proving that a retained owner path has no
  /// mounted owner; the root path still handles paths that cannot be mapped.
  @_spi(Renderer) public func _stageDependencyOwnerReplacements(_ owners: Set<UInt64>) {
    guard !disposed, !owners.isEmpty else { return }
    pendingDependencyOwnerReplacements.formUnion(owners)
  }

  /// Records a raw State read. Binding-backed controls call
  /// `_creditLeafRead` immediately before reading, so their getter does not
  /// accidentally turn a known leaf into a structural dependency.
  @_spi(Renderer) public func _recordRead(_ source: _StateSourceID) {
    guard !disposed else { return }
    recordRead(source)
  }

  /// Records a read emitted by a lowered `@Observable` member accessor. The
  /// dedicated entry point makes the registrar boundary explicit while
  /// sharing the same pass-local owner graph as ordinary State reads.
  @_spi(Renderer) @inline(__always) public func _recordPublishedObservation(_ source: _StateSourceID) {
    StateStore._recordedReads &+= 1
    EnvironmentValues._readRecorder?.stateReads &+= 1
    guard !disposed else { return }
    observationAccessCount &+= 1
    _dependencies.observationAccess(source, owner: StateRuntime.scope?.ownerToken)
  }

#if hasFeature(Embedded)
  fileprivate func _retainPublishedObservation(_ registration: _PublishedObservationRegistration) {
    guard !disposed,
          !publishedObservationRegistrations.contains(where: { $0 === registration }) else { return }
    publishedObservationRegistrations.append(registration)
  }
#endif

  /// Records a key-path `@Environment` read against the current erased-view
  /// owner. Environment storage is value based rather than observable, so one
  /// aggregate source keeps the dependency graph compact while still allowing
  /// safe owner targeting when no local environment override is involved.
  @_spi(Renderer) public func _recordEnvironmentRead() {
    guard !disposed else { return }
    // Not counted in `_recordedReads`: `EquatableView` tracks environment reads by their entries' stamps.
    _dependencies.recordRead(.environment, owner: StateRuntime.scope?.ownerToken)
  }

  /// `Observation` runs its change callbacks on whichever thread mutates the
  /// observed model, so two models changing together reach this store at once.
  /// The store and the tree behind its invalidation handler expect serialized
  /// access; this lock serializes those callbacks among themselves. (It is a
  /// no-op in Embedded and WASI builds, which run on one thread.)
  private let observationLock = _RuntimeLock()

  @_spi(Renderer) public func _ownerObservationDidChange(_ owner: UInt64) {
    observationLock.withLock {
      guard !disposed else { return }
      if _dependencies.hasObservation { observationCoalescedInvalidationCount &+= 1 }
      observationInvalidationCount &+= 1
      _dependencies.markObservation(owner)
      invalidationHandler?()
    }
  }

  @_spi(Renderer) public func _hasPendingObservationInvalidation() -> Bool {
    !disposed && _dependencies.hasObservation
  }

  @_spi(Renderer) public func _observationOwnerTokens() -> Set<UInt64> {
    guard !disposed else { return [] }
    return _dependencies.observationOwners
  }

  /// Whether an erased owner read a tracked state/observation source during
  /// the render pass currently being assembled. Fiber uses this as a
  /// conservative static-template gate: once a dynamic owner is found, its
  /// entire descendant candidate stays on the normal path. A representation
  /// can still be retained when a dynamic value happens to render the same
  /// output, but it is never labelled dependency-independent.
  @_spi(Renderer) public func _ownerReadSourcesDuringCurrentPass(_ token: UInt64) -> Bool {
    !disposed && _dependencies.ownerReadInPass(token)
  }

  /// Conservative static-template gate. A State wrapper can be read while a
  /// value view is being formed, before an erased child owner exists, so an
  /// empty owner-token set is not proof that a tree is state-independent.
  @_spi(Renderer) public func _hasStateStorage() -> Bool {
    !storage.isEmpty
  }

  @_spi(Renderer) public func _clearObservationInvalidation() {
    guard !disposed else { return }
    _dependencies.clearObservation()
  }

  @_spi(Renderer) public var _observationDiagnostics: _StateStoreObservationDiagnostics {
    _StateStoreObservationDiagnostics(
      accessCount: observationAccessCount,
      invalidationCount: observationInvalidationCount,
      coalescedInvalidationCount: observationCoalescedInvalidationCount,
      teardownCount: observationTeardownCount,
      isDisposed: disposed,
      dependencies: _dependencies.diagnostics
    )
  }

  /// Counts every state, observation and leaf read any store records. `EquatableView` only reuses a render
  /// that recorded none: a render that read state depends on more than its view value. Environment reads are
  /// not counted; `EquatableView` checks them by stamp.
  nonisolated(unsafe) static var _recordedReads = 0

  private func recordRead(_ source: _StateSourceID) {
    StateStore._recordedReads &+= 1
    EnvironmentValues._readRecorder?.stateReads &+= 1
    guard !disposed else { return }
    _dependencies.recordRead(source, owner: StateRuntime.scope?.ownerToken)
  }

  @_spi(Renderer) public func _creditLeafRead(_ source: _StateSourceID?) {
    StateStore._recordedReads &+= 1
    EnvironmentValues._readRecorder?.stateReads &+= 1
    guard !disposed, let source else { return }
    _dependencies.creditLeaf(source)
  }

  @_spi(Renderer) public func _endRenderPass(provenLeafSources: Set<_StateSourceID>) {
    finishReadPass(provenLeafSources)
  }
  @_spi(Renderer) public func _endSupplementalRenderPass(provenLeafSources: Set<_StateSourceID>) {
    finishReadPass(provenLeafSources)
  }
  @_spi(Renderer) public func _endSubtreeRenderPass(provenLeafSources: Set<_StateSourceID>) {
    finishReadPass(provenLeafSources)
  }
  private func finishReadPass(_ sources: Set<_StateSourceID>) {
    guard !disposed else { return }
    _dependencies.endPass(provenLeafSources: sources)
    recordRuntimeMemoryShape()
  }

  private func recordRuntimeMemoryShape() {
    guard _RuntimeMemoryMetrics.isEnabled else { return }
    _RuntimeMemoryMetrics.recordStateStoreShape(
      entries: storage.count,
      subscribers: subscribers.count,
      observedKeys: observedKeys.count,
      observedObjects: observedObjects.count,
      dependencyOwnerEdges: _dependencies.edgeCount
    )
  }

  @_spi(Renderer) public func _subscribe(
    _ source: _StateSourceID,
    callback: @escaping () -> Void
  ) -> _StateSubscription {
    guard !disposed else { return _StateSubscription {} }
    let id = nextSubscriberID
    nextSubscriberID &+= 1
    subscribers.append(Subscriber(source: source, id: id, callback: callback))
    #if hasFeature(Embedded)
    return _StateSubscription { self.removeSubscriber(source: source, id: id) }
    #else
    return _StateSubscription { [weak self] in self?.removeSubscriber(source: source, id: id) }
    #endif
  }

  @_spi(Renderer) public func _isStructural(_ source: _StateSourceID) -> Bool {
    !disposed && _dependencies.isStructural(source)
  }

  @_spi(Renderer) public func _hasDirtyStructuralSource() -> Bool {
    !disposed && _dependencies.hasDirtyStructural
  }

  /// Returns a unique owner for every dirty structural source. `nil` means a
  /// source is unowned or shared and therefore requires root reconciliation.
  @_spi(Renderer) public func _dirtySubtreeOwnerTokens() -> Set<UInt64>? {
    guard !disposed else { return [] }
    return _dependencies.dirtyStructuralOwners()
  }

  /// Structural `@State` owners, excluding lowered `@Observable` member
  /// sources that the Embedded publisher routes separately by source.
  @_spi(Renderer) public func _dirtyStateSubtreeOwnerTokens() -> Set<UInt64>? {
    guard !disposed else { return [] }
    return _dependencies.dirtyStructuralOwners(includingObservations: false)
  }

  /// Returns the retained readers of each changed lowered `@Observable`
  /// member independently. Keeping the source boundary lets Fiber validate
  /// every property route before combining work from one event.
  @_spi(Renderer) public func _dirtyPublishedObservationOwnerGroups() -> [UInt64: Set<UInt64>]? {
    guard !disposed else { return .init() }
    var groups: [UInt64: Set<UInt64>] = .init()
    for source in pendingPublishedObservationSources {
      guard let sourceOwners = _dependencies.dirtyOwners(of: source) else {
        return nil
      }
      groups[source.rawValue] = sourceOwners
    }
    return groups
  }

  /// Compatibility aggregate for renderer paths that only need the union.
  /// Source-aware invalidation should prefer `_dirtyPublishedObservationOwnerGroups()`.
  @_spi(Renderer) public func _dirtyPublishedObservationOwnerTokens() -> Set<UInt64>? {
    guard let groups = _dirtyPublishedObservationOwnerGroups() else { return nil }
    return groups.values.reduce(into: Set<UInt64>()) { $0.formUnion($1) }
  }

  @_spi(Renderer) public func _runAfterCommit(_ effect: @escaping () -> Void) {
    if effectDeferralDepth > 0 { deferredEffects.append(effect) } else { effect() }
  }

  @_spi(Renderer) public func _beginEffectDeferral() { effectDeferralDepth += 1 }
  @_spi(Renderer) public func _endEffectDeferral() { effectDeferralDepth -= 1 }

  @_spi(Renderer) public func _flushAfterCommitEffects() {
    guard effectDeferralDepth == 0, !deferredEffects.isEmpty else { return }
    let effects = deferredEffects
    deferredEffects.removeAll(keepingCapacity: true)
    for effect in effects { effect() }
  }

  @_spi(Renderer) public func _pendingPublishedObservationSourceCount() -> Int {
    pendingPublishedObservationSources.count
  }

  /// Returns all owners that read a dirty inherited-environment source. Unlike
  /// a structural `@State` source, an environment revision intentionally
  /// invalidates every reader, so multiple disjoint owners are safe to batch;
  /// Fiber still removes descendant targets when an ancestor is present.
  @_spi(Renderer) public func _dirtyEnvironmentOwnerTokens() -> Set<UInt64>? {
    guard !disposed else { return [] }
    return _dependencies.dirtyOwners(of: .environment)
  }

  @_spi(Renderer) public func _hasDirtySourcesOtherThanEnvironment() -> Bool {
    !disposed && _dependencies.hasDirtyOtherThan(.environment)
  }

  /// Marks the aggregate environment dependency dirty. Browser hosts invoke
  /// this while already processing their scheduled update, so notification is
  /// optional to avoid enqueueing a duplicate scheduler turn.
  @_spi(Renderer) public func _markEnvironmentChanged(notify: Bool = true) {
    guard !disposed else { return }
    _dependencies.markDirty(.environment)
    if notify { invalidationHandler?() }
  }

  @_spi(Renderer) public func _clearDirtySources() {
    guard !disposed else { return }
    _dependencies.clearDirty()
    pendingPublishedObservationSources.removeAll(keepingCapacity: true)
  }

  private func sourceDidChange(_ source: _StateSourceID) {
    guard !disposed else { return }
    if _AnimationTransactionRuntime.isActive {
      pendingAnimationCSS = _AnimationTransactionRuntime.current?.cssValue ?? "none"
      _commitTransaction = _AnimationTransactionRuntime.transaction
    }
    _dependencies.markDirty(source)
    let callbacks = subscribers.compactMap { $0.source == source ? $0.callback : nil }
    for callback in callbacks { callback() }
    invalidationHandler?()
  }

  @_spi(Renderer) public func _publishedObservationDidChange(_ source: _StateSourceID) {
    guard !disposed else { return }
    pendingPublishedObservationSources.insert(source)
    if _AnimationTransactionRuntime.isActive {
      pendingAnimationCSS = _AnimationTransactionRuntime.current?.cssValue ?? "none"
      _commitTransaction = _AnimationTransactionRuntime.transaction
    }
    if _dependencies.hasDirtyStructural || _dependencies.hasObservation {
      observationCoalescedInvalidationCount &+= 1
    }
    observationInvalidationCount &+= 1
    _dependencies.markDirty(source)
    let callbacks = subscribers.compactMap { $0.source == source ? $0.callback : nil }
    for callback in callbacks { callback() }
    invalidationHandler?()
  }

  private func removeSubscriber(source: _StateSourceID, id: UInt64) {
    subscribers.removeAll { $0.source == source && $0.id == id }
  }
  /// Replaces the object a `@StateObject` holds (`model = Model()` after the view was created).
  fileprivate func replaceObject<ObjectType: AnyObject>(_ key: String, with object: ObjectType) {
    storage[key] = _ObjectStateStoreEntry(object)
  }
  fileprivate func object<ObjectType: AnyObject>(_ key: String, create: @autoclosure () -> ObjectType) -> ObjectType {
    if let existing = storage[key] as? _ObjectStateStoreEntry<ObjectType> { return existing.object }
    let created = create()
    storage[key] = _ObjectStateStoreEntry(created)
    return created
  }
  /// Records the last concrete Equatable value without reflection. The same
  /// typed storage and change semantics are used in standard and Embedded builds.
  func remember<Value: Equatable>(_ key: String, value: Value) -> Bool {
    rememberChange(key, value: value).changed
  }

  /// Stores a value and returns the previous concrete value when one was
  /// recorded.  Keeping this operation in StateStore gives the modern
  /// `onChange` overloads the same Fiber-scoped identity semantics as the
  /// original single-value callback.
  package func rememberChange<Value: Equatable>(_ key: String, value: Value) -> (changed: Bool, previous: Value?, initial: Bool) {
    observedKeys.insert(key)
    return observedValues.remember(key, value: value)
  }

  /// Starts or restarts a SwiftUI-style `.task` owned by a Fiber path. An
  /// Equatable task ID changing cancels the previous operation before starting
  /// the replacement; disappearance clears the handle so a newly inserted
  /// view at the same path can run its task again.
  /// A counter that advances whenever the typed value (a task identity, an
  /// `.animation(_:value:)` value) stops being equal to the previously rendered one.
  package func _identityGeneration<Value: Equatable>(key: String, value: Value) -> UInt64 {
    observedKeys.insert(key)
    return observedValues.generation(key, value: value)
  }

  func startTask(key: String, id: String?, action: @escaping () async -> Void) {
    guard !disposed else { return }
    if let running = runningTasks[key] {
      if running.id == id { return }
      running.task.cancel()
    }
    // The task runs on the main actor, like the store that owns it, so it may use the closure directly.
    runningTasks[key] = (Task {
      await action()
    }, id)
  }

  func cancelTask(key: String) {
    runningTasks[key]?.task.cancel()
    runningTasks[key] = nil
  }
  public func setInvalidationHandler(_ handler: @escaping () -> Void) {
    guard !disposed else { return }
    invalidationHandler = handler
    // The initial render creates the state boxes before FiberTree installs its
    // invalidation hook. Attach the callback to those already-owned boxes so
    // async work (for example URLSession completion) can commit a new Fiber
    // snapshot without requiring an unrelated DOM event.
    for value in storage.values {
      value._reattach(to: self)
    }
  }

  /// Registers an observable model when a Fiber reads it. A published model
  /// update invalidates this store's owning tree and follows the exact same
  /// reconciliation path as a control event or `@State` update.
  func observe(_ object: AnyObject) {
    guard !disposed else { return }
    #if hasFeature(Embedded)
    // Embedded source lowering uses the key-path-free Published bridge above;
    // arbitrary protocol casts are not available in the Embedded ABI.
    _ = object
    return
    #else
    guard let observable = object as? ObservableObject else { return }
    let identifier = ObjectIdentifier(object)
    let source: _StateSourceID
    if let existing = observedObjectSources[identifier] {
      source = existing
    } else {
      source = _StateSourceID(rawValue: nextSourceID)
      nextSourceID &+= 1
      observedObjects.insert(identifier)
      observedObjectSources[identifier] = source
      // ObservableObject invalidation is aggregate by default. Until a
      // property-level binding descriptor is available, conservatively keep
      // it structural so a model write cannot skip a dependent branch.
      let publisher = observable.objectWillChange
      publisherSubscriptions.append(publisher)
      publisher.subscribe { [weak self] in self?.sourceDidChange(source) }
    }
    _dependencies.observeAggregate(source, owner: StateRuntime.scope?.ownerToken)
    #endif
  }

  public init() {
    _RuntimeMemoryMetrics.recordStateStoreInit()
  }

  @_spi(Renderer) public var _isDisposed: Bool { disposed }
}

/// Class erasure keeps heterogeneous state slots without an `Any` payload
/// or an existential conformance lookup in the Embedded runtime.
@MainActor package class _StateStoreEntry {
  func _reattach(to store: StateStore) {}
  func _detach() {}
  #if DEBUG
  /// Development loop (StateSnapshot.swift): the value as text with the tag of its type, for a state that has one.
  func _snapshot() -> (tag: String, text: String)? { nil }
  /// Takes a value an earlier page saved, when it was saved by a state of the same type.
  func _restore(tag: String, text: String) {}
  #endif
}

@MainActor private final class _ObjectStateStoreEntry<ObjectType: AnyObject>: _StateStoreEntry {
  let object: ObjectType
  init(_ object: ObjectType) { self.object = object }
}

@MainActor final package class StateScope {
  let store: StateStore
  let path: _FiberPath
  let ownerToken: UInt64?
  /// Distinguishes a parent from its only child: a single child gets no
  /// builder key, so both scopes share one path and would otherwise hand out
  /// the same `#stateN` slot to different properties.
  let viewTag: String
  var counter = 0
  private var keysByBox: [ObjectIdentifier: String] = .init()
  package init(context: _RenderContext, viewTag: String) { store = context.stateStore; path = context._fiberPath; ownerToken = context._renderOwnerToken; self.viewTag = viewTag }
  func key() -> String { defer { counter += 1 }; return path.description + "#state\(counter)@" + viewTag }
  func key<Object: AnyObject>(for box: Object) -> String {
    // Generic Object is a concrete class specialization, not an AnyObject
    // existential. Embedded can form its ObjectIdentifier. Repeated reads of
    // one property must never bind it to the next property's state slot.
    let identifier = ObjectIdentifier(box)
    if let key = keysByBox[identifier] { return key }
    let key = self.key()
    keysByBox[identifier] = key
    return key
  }
  func key<Value>(forMemberID memberID: UInt32, type: Value.Type) -> String {
    key(forMemberID: memberID, typeName: _swiftUIWebTypeName(type))
  }
  /// The text of `key(forMemberID:type:)`, out of the generic function so it is compiled once rather than once per type.
  private func key(forMemberID memberID: UInt32, typeName: String) -> String {
    let pathDescription = path.description
    return "\(pathDescription)#state-member:\(memberID):\(typeName)@\(viewTag)"
  }
}

package enum StateRuntime {
  /// The state scope of the view currently being evaluated on this thread. The scope is
  /// thread-local, so reading it needs no actor hop; the scope's own members stay main-actor.
  nonisolated static package var scope: StateScope? {
    get { _RenderThreadState.current.stateScope }
    set { _RenderThreadState.current.stateScope = newValue }
  }
}

@MainActor final package class StateBox<Value>: _StateStoreEntry {
  package var value: Value {
    didSet {
      if !suppressNotifications { onChange?() }
    }
  }
  /// Set while the renderer flips the value to learn its visual effect; the
  /// change must not reach observers or schedule an update.
  var suppressNotifications = false
  /// Set for `Equatable` values: writing an equal value changes nothing, so it
  /// must not invalidate anything.
  var isEqual: ((Value, Value) -> Bool)?
  #if DEBUG
  // Set for a value type the development loop can keep across a reload (`_WriteEquatable._stateSnapshotTag`). They
  // capture nothing, so the box owns no reference to itself.
  var _snapshotTag = ""
  var _snapshotEncode: ((Value) -> String)?
  var _snapshotDecode: ((Substring) -> Value?)?
  override func _snapshot() -> (tag: String, text: String)? { _snapshotEncode.map { (_snapshotTag, $0(value)) } }
  override func _restore(tag: String, text: String) {
    guard tag == _snapshotTag, let restored = _snapshotDecode?(Substring(text)) else { return }
    nonisolated(unsafe) let restoredValue = restored
    // The page is being mounted: nothing has read the value yet, so there is no one to tell.
    let wasSuppressed = suppressNotifications
    suppressNotifications = true
    value = restoredValue
    suppressNotifications = wasSuppressed
  }
  #endif
  func assign(_ newValue: Value) {
    nonisolated(unsafe) let newValue = newValue
    if let isEqual, isEqual(value, newValue) { return }
    value = newValue
  }
  var onChange: (() -> Void)?
  package var onRead: (() -> Void)?
  var sourceID: _StateSourceID?
  init(_ value: Value) {
    self.value = value
    _RuntimeMemoryMetrics.recordStateBoxInit()
  }
  deinit { _RuntimeMemoryMetrics.recordStateBoxDeinit() }
  override func _reattach(to store: StateStore) { store._reattach(self) }
  override func _detach() {
    onRead = nil
    onChange = nil
  }
}

@MainActor private final class StateStorage<Value> {
  var box: StateBox<Value>
  var ownerStoreID: ObjectIdentifier?
  let adoptedLazily: Bool
  let initializedWithActiveScope: Bool
  let memberID: UInt32
  init(
    _ box: StateBox<Value>,
    store: StateStore? = nil,
    memberID: UInt32 = 0,
    initializedWithActiveScope: Bool = false
  ) {
    self.box = box
    ownerStoreID = store.map { ObjectIdentifier($0) }
    adoptedLazily = store == nil
    self.initializedWithActiveScope = initializedWithActiveScope
    self.memberID = memberID
    _RuntimeMemoryMetrics.recordStateStorageInit()
  }
  deinit { _RuntimeMemoryMetrics.recordStateStorageDeinit() }

  /// The box a `State` wrapper resolves to in the current render scope, adopting it into the scope's store.
  func registeredStateBox() -> StateBox<Value> {
    guard let scope = StateRuntime.scope else { return box }
    // A wrapper already attached by its declaration must not be adopted again
    // by whichever child happens to read it next. This was aliasing independent
    // properties after navigation and even on two reads of the same property.
    let key: String?
    if memberID != 0 {
      key = scope.key(forMemberID: memberID, type: Value.self)
    } else {
      key = adoptedLazily ? scope.key(for: self) : nil
    }
    if ownerStoreID == ObjectIdentifier(scope.store) { return box }
    let registered = scope.store.register(
      box,
      key: key ?? scope.key(),
      reuseMatchingSlot: memberID != 0 ||
        (adoptedLazily && (initializedWithActiveScope || !scope.path.isEmpty))
    )
    box = registered
    ownerStoreID = ObjectIdentifier(scope.store)
    return registered
  }

  /// The box a `FocusState` wrapper resolves to in the current render scope.
  func registeredFocusBox() -> StateBox<Value> {
    guard let scope = StateRuntime.scope else { return box }
    let key = adoptedLazily ? scope.key(for: self) : nil
    if ownerStoreID == ObjectIdentifier(scope.store) { return box }
    let registered = scope.store.register(box, key: key ?? scope.key())
    box = registered
    ownerStoreID = ObjectIdentifier(scope.store)
    return registered
  }
}

/// Plain value types for which "the new value equals the old one" is decidable
/// from the before/after values: no shared storage that a get-modify-set could
/// mutate in place. A write of an equal value to state of these types
/// invalidates nothing. Other `Equatable` types keep notifying on every write.
public protocol _WriteEquatable: Equatable {
  /// Development loop: a tag for the type when a state of it can be kept across a reload, empty when it cannot
  /// (StateSnapshot.swift). The three members have defaults that keep nothing.
  static var _stateSnapshotTag: String { get }
  static func _stateSnapshotText(_ value: Self) -> String
  static func _stateSnapshotValue(_ text: Substring) -> Self?
}
extension _WriteEquatable {
  public static var _stateSnapshotTag: String { "" }
  public static func _stateSnapshotText(_ value: Self) -> String { "" }
  public static func _stateSnapshotValue(_ text: Substring) -> Self? { nil }
}
extension Bool: _WriteEquatable {}
extension Int: _WriteEquatable {}
extension Int8: _WriteEquatable {}
extension Int16: _WriteEquatable {}
extension Int32: _WriteEquatable {}
extension Int64: _WriteEquatable {}
extension UInt: _WriteEquatable {}
extension UInt8: _WriteEquatable {}
extension UInt16: _WriteEquatable {}
extension UInt32: _WriteEquatable {}
extension UInt64: _WriteEquatable {}
extension Double: _WriteEquatable {}
extension Float: _WriteEquatable {}
extension String: _WriteEquatable {}
extension Character: _WriteEquatable {}
extension Optional: _WriteEquatable where Wrapped: _WriteEquatable {}
extension Array: _WriteEquatable where Element: _WriteEquatable {}
extension Set: _WriteEquatable where Element: _WriteEquatable {}

@propertyWrapper public struct State<Value>: DynamicProperty {
  private let storage: StateStorage<Value>
  public init(wrappedValue: Value) where Value: _WriteEquatable {
    self.init(_uncheckedWrappedValue: wrappedValue, memberID: 0)
    let storage = self.storage
    _assumeMainActor { storage.box.isEqual = { $0 == $1 }; Self._keepAcrossReloads(storage.box) }
  }
  public init(wrappedValue: Value) {
    self.init(_uncheckedWrappedValue: wrappedValue, memberID: 0)
  }
  /// Development loop: a state of a type that has a text form is kept across a reload of the page (StateSnapshot.swift).
  @MainActor private static func _keepAcrossReloads(_ box: StateBox<Value>) where Value: _WriteEquatable {
    #if DEBUG
    guard _StateSnapshots.enabled, !Value._stateSnapshotTag.isEmpty else { return }
    box._snapshotTag = Value._stateSnapshotTag
    box._snapshotEncode = { Value._stateSnapshotText($0) }
    box._snapshotDecode = { Value._stateSnapshotValue($0) }
    #endif
  }
  /// Renderer SPI used by the source lowerer for member-identified state.
  @_spi(Renderer) public init(wrappedValue: Value, memberID: UInt32) where Value: _WriteEquatable {
    self.init(_uncheckedWrappedValue: wrappedValue, memberID: memberID)
    let storage = self.storage
    _assumeMainActor { storage.box.isEqual = { $0 == $1 }; Self._keepAcrossReloads(storage.box) }
  }
  @_spi(Renderer) public init(wrappedValue: Value, memberID: UInt32) {
    self.init(_uncheckedWrappedValue: wrappedValue, memberID: memberID)
  }
  /// SwiftUI's explicit spelling, used when a view's initializer assigns `_state = State(initialValue: ...)`.
  public init(initialValue value: Value) { self.init(wrappedValue: value) }
  private init(_uncheckedWrappedValue wrappedValue: Value, memberID: UInt32) {
    nonisolated(unsafe) let wrappedValue = wrappedValue
    // Child view values are formed while their parent's body is being built,
    // so an active StateRuntime scope here belongs to the parent. Defer store
    // adoption until the wrapper is first read inside its own erased render
    // boundary; otherwise inserting a conditional sibling can shift every
    // later child's @State slot onto the newly inserted view.
    let initializedWithActiveScope = StateRuntime.scope != nil
    storage = _assumeMainActor {
      StateStorage(
        StateBox(wrappedValue),
        memberID: memberID,
        initializedWithActiveScope: initializedWithActiveScope
      )
    }
  }
  public var wrappedValue: Value {
    get {
      let storage = self.storage
      return _assumeMainActor {
        let box = storage.registeredStateBox()
        box.onRead?()
        return box.value
      }
    }
    nonmutating set {
      let storage = self.storage
      nonisolated(unsafe) let newValue = newValue
      _assumeMainActor { storage.registeredStateBox().assign(newValue) }
    }
  }
  public var projectedValue: Binding<Value> {
    // Capture the reference storage rather than the wrapper value.  A
    // projected binding escapes the view's body and may be invoked after the
    // view has been copied by the reconciler.  Capturing `self` here makes the
    // closure retain a wrapper copy; on WebAssembly that can expose stale
    // wrapper fields when several @State properties are projected together.
    // StateBox is the identity-bearing storage, so capturing it directly
    // preserves SwiftUI's value-wrapper semantics across all targets.
    let storage = self.storage
    return _assumeMainActor {
      let box = storage.registeredStateBox()
      return Binding(
        sourceID: box.sourceID,
        sourceStore: StateRuntime.scope?.store,
        get: { box.onRead?(); return box.value },
        set: { box.assign($0) }
      )
    }
  }

  fileprivate func registeredBoxForRenderer() -> StateBox<Value> {
    let storage = self.storage
    return _assumeMainActor { storage.registeredStateBox() }
  }

  /// Installs the state in the current render scope (`View._installState`): its storage takes the box of the view's
  /// identity, so later reads, in the body or in an action that runs outside any scope, see that box. Records no read.
  public func _install() {
    let storage = self.storage
    _assumeMainActor { _ = storage.registeredStateBox() }
  }
}

extension State: _InstallableState {}

/// SwiftUI-shaped focus state. Focus is ordinary Fiber-owned state; the
/// browser host only sees the `focus`/`blur` event metadata emitted by the
/// corresponding modifier.
@propertyWrapper public struct FocusState<Value: Hashable>: DynamicProperty {
  // FocusState is commonly initialized before Fiber evaluates the owning
  // view, just like @State. Keep reference storage so its projected Binding
  // can be adopted into the current semantic store instead of mutating an
  // unattached box that the browser will never observe.
  private let storage: StateStorage<Value>

  // Apple's FocusState has no `init(wrappedValue:)`: `@FocusState var f = false`
  // does not compile in SwiftUI, so the only initializers are the two below.
  private init(defaultValue: Value) {
    nonisolated(unsafe) let defaultValue = defaultValue
    storage = _assumeMainActor {
      if let scope = StateRuntime.scope {
        return StateStorage(scope.store.box(scope.key(), default: defaultValue), store: scope.store)
      } else {
        return StateStorage(StateBox(defaultValue))
      }
    }
  }

  public init() where Value == Bool { self.init(defaultValue: false) }
  public init<T: Hashable>() where Value == T? { self.init(defaultValue: nil) }

  public var wrappedValue: Value {
    get {
      let storage = self.storage
      return _assumeMainActor { let box = storage.registeredFocusBox(); box.onRead?(); return box.value }
    }
    nonmutating set {
      let storage = self.storage
      nonisolated(unsafe) let newValue = newValue
      _assumeMainActor { storage.registeredFocusBox().value = newValue }
    }
  }

  /// `@FocusState.Binding var isFocused: Bool`: the projection of a FocusState, passed to a child view.
  @propertyWrapper public struct Binding {
    package let binding: SwiftUIWebCore.Binding<Value>
    init(_ binding: SwiftUIWebCore.Binding<Value>) { self.binding = binding }
    public var wrappedValue: Value {
      get { binding.wrappedValue }
      nonmutating set { binding.wrappedValue = newValue }
    }
    public var projectedValue: Binding { self }
  }

  public var projectedValue: Binding {
    let storage = self.storage
    return _assumeMainActor {
      let box = storage.registeredFocusBox()
      return Binding(SwiftUIWebCore.Binding(
        sourceID: box.sourceID,
        sourceStore: StateRuntime.scope?.store,
        get: { box.onRead?(); return box.value },
        set: { box.value = $0 }
      ))
    }
  }
}

@MainActor private final class _StateObjectStorage<ObjectType: AnyObject> {
  // Written once by the nonisolated `StateObject` initializer; only the main actor calls it.
  private nonisolated(unsafe) let create: () -> ObjectType
  private var object: ObjectType?
  /// Where the object was last read from, so a later assignment can replace it in the store.
  var attachedStore: StateStore?
  var attachedKey: String?

  nonisolated init(create: @escaping () -> ObjectType) {
    self.create = create
  }

  func seed() -> ObjectType {
    if let object { return object }
    let object = create()
    self.object = object
    return object
  }

  func adopt(_ object: ObjectType) {
    self.object = object
  }
}

@MainActor @preconcurrency
@propertyWrapper public struct StateObject<ObjectType: AnyObject>: DynamicProperty {
  private let storage: _StateObjectStorage<ObjectType>

  nonisolated public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) {
    storage = _StateObjectStorage(create: thunk)
  }

  @MainActor @preconcurrency public var wrappedValue: ObjectType {
    get { _read() }
    nonmutating set {
      storage.adopt(newValue)
      if let store = storage.attachedStore, let key = storage.attachedKey {
        store.replaceObject(key, with: newValue)
        store.observe(newValue)
      }
    }
  }

  private func _read() -> ObjectType {
    guard let scope = StateRuntime.scope else { return storage.seed() }
    let object = _attach(in: scope)
    scope.store.observe(object)
    return object
  }

  /// The object of the view's identity in `scope`'s store, which this wrapper adopts.
  private func _attach(in scope: StateScope) -> ObjectType {
    let key = scope.key(for: storage)
    let object = scope.store.object(key, create: storage.seed())
    storage.adopt(object)
    storage.attachedStore = scope.store
    storage.attachedKey = key
    return object
  }

  /// Installs the object in the current render scope (`View._installState`): an action that runs outside any scope
  /// then reads the object of the view's identity, not the one this value of the view would create. Observes nothing.
  public func _install() {
    guard let scope = StateRuntime.scope else { return }
    _ = _attach(in: scope)
  }

#if hasFeature(Embedded)
  // Key paths do not exist here: the source lowering turns `$model.member` into `_memberBinding`, so `$model`
  // itself is the Binding SwiftUI's `@State` projects for an observable class.
  public var projectedValue: Binding<ObjectType> {
    Binding(get: { self.wrappedValue }, set: { self.wrappedValue = $0 })
  }
#else
  /// `$model.member` goes through `ObservedObject.Wrapper`'s dynamic member lookup, as in SwiftUI.
  @MainActor @preconcurrency public var projectedValue: ObservedObject<ObjectType>.Wrapper {
    ObservedObject<ObjectType>.Wrapper { self.wrappedValue }
  }
#endif
}

extension StateObject: _InstallableState {}

/// A property a view's state scope installs before the view's body is formed (`View._installState`).
protocol _InstallableState {
  @MainActor func _install()
}

#if !hasFeature(Embedded)
/// View types none of whose stored properties is installable state, so their bodies skip the reflection.
@MainActor private var _viewTypesWithoutState: Set<ObjectIdentifier> = []

/// `View._installState` where there is reflection: installs every `@State` and `@StateObject` of `view`, in the order
/// they are declared, so their slots in the scope are the same on every render.
@MainActor func _installStateByReflection<V: View>(_ view: V) {
  guard StateRuntime.scope != nil else { return }
  let type = ObjectIdentifier(V.self)
  if _viewTypesWithoutState.contains(type) { return }
  var installed = false
  for child in Mirror(reflecting: view).children {
    guard let state = child.value as? any _InstallableState else { continue }
    state._install()
    installed = true
  }
  if !installed { _viewTypesWithoutState.insert(type) }
}
#endif

@MainActor @preconcurrency @propertyWrapper public struct ObservedObject<ObjectType: AnyObject>: DynamicProperty {
  /// `$model`: reads the object through the view's observation scope on each access, so
  /// `$model.member` forms a binding to the member only when the body asks for it.
  @MainActor @dynamicMemberLookup @preconcurrency public struct Wrapper {
    private let object: () -> ObjectType
    fileprivate init(_ object: @escaping () -> ObjectType) { self.object = object }
    @MainActor @preconcurrency public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
      let object = self.object()
      return Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
    }
  }

  private var object: ObjectType
  @MainActor @preconcurrency public init(wrappedValue: ObjectType) { object = wrappedValue }
  @MainActor @preconcurrency public var wrappedValue: ObjectType {
    get {
      StateRuntime.scope?.store.observe(object)
      return object
    }
    set { object = newValue }
  }
  @MainActor @preconcurrency public var projectedValue: ObservedObject<ObjectType>.Wrapper {
    let source = self
    return Wrapper { source.wrappedValue }
  }
}

/// SwiftUI-shaped bindings for reference models.  `@Bindable` deliberately
/// works with any reference type that exposes writable key paths, including
/// models annotated with Swift's standard `@Observable` macro and existing
/// `ObservableObject` models.  Observation itself remains an implementation
/// detail: the wrapper only projects ordinary SwiftUIWeb `Binding` values.
@dynamicMemberLookup @propertyWrapper public struct Bindable<Value>: DynamicProperty {
  private final class Storage {
    var object: Value
    init(_ object: Value) { self.object = object }
  }
  private let storage: Storage

  public init(wrappedValue: Value) { storage = Storage(wrappedValue) }

  /// `Bindable(model).title`: a binding made in place, without declaring a `@Bindable` property.
  public init(_ wrappedValue: Value) { storage = Storage(wrappedValue) }

  public init(projectedValue: Bindable<Value>) { storage = projectedValue.storage }

  public var wrappedValue: Value {
    get { storage.object }
    nonmutating set { storage.object = newValue }
  }

  public var projectedValue: Bindable<Value> { self }

  public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> {
    // Forming a binding is part of the view's body evaluation. Read the
    // projected member once here so a native @Observable model records the
    // dependency even when the eventual control reads its binding outside
    // the parent's Observation tracking scope.
    _ = storage.object[keyPath: keyPath]
    let storage = self.storage
    return Binding(
      _unchecked: { storage.object[keyPath: keyPath] },
      set: { newValue in
        // Copy the reference/value out of the wrapper before key-path
        // writeback. Observation can synchronously invalidate the Fiber tree
        // from a model setter; avoiding a long-lived access to `storage`
        // prevents Swift's exclusivity checker from seeing that re-entrant
        // render as an overlapping modification.
        let object = storage.object
        object[keyPath: keyPath] = newValue
        storage.object = object
      }
    )
  }
}

/// The Embedded lowering of `$model.member`: a binding to a member of a model, reading the member once so the
/// declaring body observes it.
@MainActor public func _memberBinding<Value>(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) -> Binding<Value> {
  _ = get()
  return Binding(get: get, set: set)
}

@dynamicMemberLookup @propertyWrapper public struct Binding<Value> {
  // Apple's Binding is nonisolated and keeps `@isolated(any)` closures; the closures stay
  // isolated to whatever actor formed them (the main actor for view code) and are called
  // through `_erasingIsolation`, as the state runtime is single-threaded.
  private let getter: () -> Value
  private let setter: (Value) -> Void
  @_spi(Renderer) public let _sourceID: _StateSourceID?
  package let _sourceStore: StateStore?
  @preconcurrency public init(
    @_inheritActorContext get: @escaping @isolated(any) @Sendable () -> Value,
    @_inheritActorContext set: @escaping @isolated(any) @Sendable (Value) -> Void
  ) {
    _sourceID = nil; _sourceStore = nil
    #if hasFeature(Embedded)
    getter = _erasingIsolation(get); setter = _erasingIsolation(set)
    #else
    if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) {
      getter = _erasingIsolation(get); setter = _erasingIsolation(set)
    } else {
      fatalError("Binding(get:set:) requires the @isolated(any) runtime of macOS 15 or newer")
    }
    #endif
  }
  package init(
    sourceID: _StateSourceID?,
    sourceStore: StateStore?,
    get: @escaping () -> Value,
    set: @escaping (Value) -> Void
  ) {
    getter = get; setter = set; _sourceID = sourceID; _sourceStore = sourceStore
  }
  public var wrappedValue: Value {
    get {
      if let store = _sourceStore {
        let id = _sourceID
        _assumeMainActor { store._creditLeafRead(id) }
      }
      return getter()
    }
    nonmutating set { setter(newValue) }
  }
  /// Reads the binding without crediting it as a leaf control dependency.
  /// Containers such as `TabView` use their selection to choose structural
  /// subtrees, so a change must reconcile the container instead of only
  /// patching a native input property. Ordinary controls continue to use the
  /// public `wrappedValue` accessor and retain the leaf fast path.
  @_spi(Renderer) public func _readForRenderer() -> Value { getter() }
  public var projectedValue: Binding<Value> { self }
  /// Lets `{ $item in ... }` (a closure that receives a binding) and `@Binding` memberwise initializers take `$value`.
  public init(projectedValue: Binding<Value>) { self = projectedValue }
  /// Framework-internal bindings over values the framework itself keeps on the main actor. Unlike the public
  /// initializer, the closures are not `@Sendable`, so they may capture non-`Sendable` bindings, key paths and models.
  package init(_unchecked get: @escaping () -> Value, set: @escaping (Value) -> Void) {
    self.init(sourceID: nil, sourceStore: nil, get: get, set: set)
  }
  public static func constant(_ value: Value) -> Binding<Value> { Binding(sourceID: nil, sourceStore: nil, get: { value }, set: { _ in }) }
  public subscript<Member>(dynamicMember keyPath: WritableKeyPath<Value, Member>) -> Binding<Member> {
    // A projected @State/@Bindable binding may be consumed by a primitive
    // control after the owning body's tracking scope has ended. Establishing
    // the member read while the binding is formed keeps native Observation
    // dependency tracking precise without requiring a second registrar.
    _ = self.wrappedValue[keyPath: keyPath]
    return Binding<Member>(sourceID: _sourceID, sourceStore: _sourceStore, get: { self.wrappedValue[keyPath: keyPath] }, set: { newValue in
      var value = self.wrappedValue; value[keyPath: keyPath] = newValue; self.wrappedValue = value
    })
  }
  @_spi(Renderer) public func map<SubValue>(get: @escaping (Value) -> SubValue, set: @escaping (Value, SubValue) -> Void) -> Binding<SubValue> {
    Binding<SubValue>(sourceID: _sourceID, sourceStore: _sourceStore, get: { get(self.wrappedValue) }, set: { set(self.wrappedValue, $0) })
  }
}

extension Binding: @unchecked Sendable where Value: Sendable {}

// A binding to a mutable collection is a collection of bindings to its elements, as in SwiftUI.
extension Binding: Sequence where Value: MutableCollection {
  public typealias Element = Binding<Value.Element>
  public typealias Iterator = IndexingIterator<Binding<Value>>
  public typealias SubSequence = Slice<Binding<Value>>
}

extension Binding: Collection where Value: MutableCollection {
  public typealias Index = Value.Index
  public typealias Indices = Value.Indices
  public var startIndex: Index { wrappedValue.startIndex }
  public var endIndex: Index { wrappedValue.endIndex }
  public var indices: Indices { wrappedValue.indices }
  public func index(after i: Binding<Value>.Index) -> Binding<Value>.Index { wrappedValue.index(after: i) }
  public func formIndex(after i: inout Binding<Value>.Index) { wrappedValue.formIndex(after: &i) }
  public subscript(position: Binding<Value>.Index) -> Binding<Value>.Element {
    Binding<Value.Element>(sourceID: _sourceID, sourceStore: _sourceStore, get: { self.wrappedValue[position] }, set: { self.wrappedValue[position] = $0 })
  }
}

extension Binding: BidirectionalCollection where Value: BidirectionalCollection, Value: MutableCollection {
  public func index(before i: Binding<Value>.Index) -> Binding<Value>.Index { wrappedValue.index(before: i) }
  public func formIndex(before i: inout Binding<Value>.Index) { wrappedValue.formIndex(before: &i) }
}

extension Binding: RandomAccessCollection where Value: RandomAccessCollection, Value: MutableCollection {}

extension State where Value == Bool {
  /// A setter for the box this state resolves to *now*, in the current render
  /// scope. The renderer flips it later, outside any scope, to learn the
  /// hovered look; capturing the registered box here guarantees it flips the
  /// one a later render of the same view reads, not a stand-in created before
  /// the state was adopted by the store. The setter changes the value without
  /// notifying anyone and returns the previous one.
  @_spi(Renderer) public func _silentSetter() -> (Bool) -> Bool {
    let box = registeredBoxForRenderer()
    return { newValue in
      _assumeMainActor {
        let previous = box.value
        box.suppressNotifications = true
        box.value = newValue
        box.suppressNotifications = false
        return previous
      }
    }
  }
}
